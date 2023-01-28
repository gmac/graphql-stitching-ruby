# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Plan
      attr_reader :operations

      SUPPORTED_OPERATIONS = ["query", "mutation"]

      def initialize(graph_info:, document:, operation_name: nil)
        @graph_info = graph_info
        @document = document
        @operation_name = operation_name
        @sequence_key = 0
        @operations = []
      end

      def plan
        build_root_operations
        expand_abstract_boundaries
        @operations.reverse!
        self
      end

      def as_json
        { ops: @operations.map(&:as_json) }
      end

      private

      def document_operation
        @document_operation ||= begin
          operation_defs = @document.definitions.select do |d|
            next unless d.is_a?(GraphQL::Language::Nodes::OperationDefinition)
            next unless SUPPORTED_OPERATIONS.include?(d.operation_type)
            @operation_name ? d.name == @operation_name : true
          end

          if operation_defs.length < 1
            raise @operation_name ? "Invalid root operation name." : "No root operation."
          elsif operation_defs.length > 1
            raise "An operation name is required when sending multiple operations."
          end

          operation_defs.first
        end
      end

      def document_variables
        @document_variables ||= document_operation.variables.each_with_object({}) do |v, memo|
          memo[v.name] = v.type
        end
      end

      def document_fragments
        @document_fragments ||= @document.definitions.each_with_object({}) do |d, memo|
          memo[d.name] = d if d.is_a?(GraphQL::Language::Nodes::FragmentDefinition)
        end
      end

      def add_operation(location:, parent_type:, operation_type: "query", after_key: nil, boundary: nil, insertion_path: [])
        operation_key = @sequence_key += 1
        selection_set, variables = yield(operation_key)
        @operations << Operation.new(
          key: operation_key,
          after_key: after_key,
          location: location,
          parent_type: parent_type,
          operation_type: operation_type,
          selections: selection_set,
          variables: variables,
          insertion_path: insertion_path,
          boundary: boundary,
        )
        @operations.last
      end

      def build_root_operations
        case document_operation.operation_type
        when "query"
          # plan steps grouping all fields by location for async execution
          parent_type = @graph_info.schema.query

          selections_by_location = document_operation.selections.each_with_object({}) do |node, memo|
            location = @graph_info.locations_by_field[parent_type.graphql_name][node.name].last
            memo[location] ||= []
            memo[location] << node
          end

          selections_by_location.map do |location, selections|
            add_operation(location: location, parent_type: parent_type) do |parent_key|
              extract_locale_selections(parent_key, parent_type, selections, [], location)
            end
          end

        when "mutation"
          # plan steps grouping sequential fields by location for sync execution
          parent_type = @graph_info.schema.mutation
          location_groups = []

          document_operation.selections.reduce(nil) do |last_location, node|
            location = @graph_info.locations_by_field[parent_type.graphql_name][node.name].last
            if location != last_location
              location_groups << {
                location: location,
                selections: [],
              }
            end
            location_groups.last[:selections] << node
            location
          end

          location_groups.reduce(nil) do |parent_key, g|
            op = add_operation(location: g[:location], parent_type: parent_type, after_key: parent_key) do |parent_key|
              extract_locale_selections(parent_key, parent_type, g[:selections], [], g[:location])
            end
            op.key
          end

        else
          raise "Invalid operation type."
        end
      end

      def extract_locale_selections(parent_key, parent_type, input_selections, insertion_path, current_location)
        remote_selections = []
        selections_result = []
        variables_result = {}

        if parent_type.kind.name == "INTERFACE"
          # fields of a merged interface may not belong to the interface at the local level,
          # so these non-local interface fields get expanded into typed fragments to be resolved
          local_interface_fields = @graph_info.fields_by_location[parent_type.graphql_name][current_location]
          extended_selections = []

          input_selections.reject! do |node|
            if node.is_a?(GraphQL::Language::Nodes::Field) && !local_interface_fields.include?(node.name)
              extended_selections << node
              true
            end
          end

          possible_types = Util.get_possible_types(@graph_info.schema, parent_type)
          possible_types.each do |possible_type|
            next if possible_type.kind.abstract? # ignore child interfaces

            # @todo need composer validation for...
            # possible_type_fields = @graph_info.locations_by_field[possible_type.graphql_name]
            # fragment_selections = extended_interface_selections.select { possible_type_fields[_1.name] }
            # if fragment_selections.any?

            # trust that the composer has validated the presence of compatible fields...
            type_name = GraphQL::Language::Nodes::TypeName.new(name: possible_type.graphql_name)
            input_selections << GraphQL::Language::Nodes::InlineFragment.new(type: type_name, selections: extended_selections)
          end
        end

        input_selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            next unless parent_type.kind.fields?

            field_type = Util.get_named_type(parent_type.fields[node.name].type)
            possible_locations = @graph_info.locations_by_field[parent_type.graphql_name][node.name]

            if !possible_locations.include?(current_location)
              remote_selections << node
            elsif Util.is_leaf_type?(field_type)
              extract_node_variables!(node, variables_result)
              selections_result << node
            else
              extract_node_variables!(node, variables_result)
              expanded_path = [*insertion_path, node.alias || node.name]
              selection_set, variables = extract_locale_selections(parent_key, field_type, node.selections, expanded_path, current_location)
              selections_result << node.merge(selections: selection_set)
              variables_result.merge!(variables)
            end

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = @graph_info.schema.types[node.type.name]
            selection_set, variables = extract_locale_selections(parent_key, fragment_type, node.selections, insertion_path, current_location)
            selections_result << node.merge(selections: selection_set)
            variables_result.merge!(variables)

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = document_fragments[node.name]
            fragment_type = @graph_info.schema.types[fragment.type.name]
            selection_set, variables = extract_locale_selections(parent_key, fragment_type, fragment.selections, insertion_path, current_location)
            selections_result << GraphQL::Language::Nodes::InlineFragment.new(type: fragment.type, selections: selection_set)
            variables_result.merge!(variables)

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        # rescue
        #   byebug
        end

        if remote_selections.any?
          selection_set = build_child_operations(parent_key, parent_type, remote_selections, insertion_path, current_location)
          selections_result.concat(selection_set)
        end

        if parent_type.kind.abstract?
          selections_result << GraphQL::Language::Nodes::Field.new(alias: "_STITCH_typename", name: "__typename")
        end

        return selections_result, variables_result
      end

      def build_child_operations(parent_key, parent_type, input_selections, insertion_path, current_location)
        parent_selections_result = []
        selections_by_location = {}

        # distribute unique fields among locations
        input_selections.reject! do |node|
          possible_locations = @graph_info.locations_by_field[parent_type.graphql_name][node.name]
          if possible_locations.length == 1
            selections_by_location[possible_locations.first] ||= []
            selections_by_location[possible_locations.first] << node
            true
          end
        end

        # distribute non-unique fields among locations
        if input_selections.any?
          location_weights = input_selections.each_with_object({}) do |node, memo|
            possible_locations = @graph_info.locations_by_field[parent_type.graphql_name][node.name]
            possible_locations.each do |location|
              memo[location] ||= 0
              memo[location] += 1
            end
          end

          input_selections.each do |node|
            possible_locations = @graph_info.locations_by_field[parent_type.graphql_name][node.name]

            preferred_location_score = 0
            preferred_location = possible_locations.reduce(possible_locations.first) do |current, candidate|
              score = selections_by_location[location] ? input_selections.length : 0
              score += location_weights.fetch(candidate, 0)

              if score > preferred_location_score
                preferred_location_score = score
                candidate
              else
                current
              end
            end

            selections_by_location[preferred_location] ||= []
            selections_by_location[preferred_location] << node
          end
        end

        routes = @graph_info.route_to_locations(parent_type.graphql_name, current_location, selections_by_location.keys)
        routes.values.each_with_object({}) do |route, memo|
          route.reduce(nil) do |parent_op, boundary|
            location = boundary["location"]
            next memo[location] if memo[location]

            selections = selections_by_location[location]
            child_op = memo[location] = add_operation(
              after_key: parent_key,
              location: location,
              parent_type: parent_type,
              insertion_path: insertion_path,
              boundary: boundary
            ) do |next_parent_key|
              if selections
                extract_locale_selections(next_parent_key, parent_type, selections, insertion_path, location)
              else
                [[], {}]
              end
            end

            foreign_key = GraphQL::Language::Nodes::Field.new(
              alias: "_STITCH_#{boundary["selection"]}",
              name: boundary["selection"]
            )

            if parent_op
              parent_op.selections << foreign_key
            else
              parent_selections_result << foreign_key
            end

            child_op
          end
        end

        parent_selections_result
      end

      def extract_node_variables!(node_with_args, variables={})
        node_with_args.arguments.each_with_object(variables) do |argument, memo|
          case argument.value
          when GraphQL::Language::Nodes::InputObject
            extract_variables(argument.value, memo)
          when GraphQL::Language::Nodes::VariableIdentifier
            memo[argument.value.name] ||= document_variables[argument.value.name]
          end
        end
      end

      # expand concrete type selections into typed fragments when sending to abstract boundaries
      def expand_abstract_boundaries
        @operations.each do |op|
          next unless op.boundary

          boundary_type = @graph_info.schema.get_type(op.boundary["type_name"])
          next unless boundary_type.kind.abstract?

          unless op.parent_type.kind.abstract?
            to_typed_selections = []
            op.selections.reject! do |node|
              if node.is_a?(GraphQL::Language::Nodes::Field)
                to_typed_selections << node
                true
              end
            end

            if to_typed_selections.any?
              type_name = GraphQL::Language::Nodes::TypeName.new(name: op.parent_type.graphql_name)
              op.selections << GraphQL::Language::Nodes::InlineFragment.new(type: type_name, selections: to_typed_selections)
            end
          end

          op.selections << GraphQL::Language::Nodes::Field.new(alias: "_STITCH_typename", name: "__typename")
        end
      end
    end
  end
end
