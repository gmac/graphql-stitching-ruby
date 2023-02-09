# frozen_string_literal: true

module GraphQL
  module Stitching
    class Planner
      SUPERGRAPH_LOCATIONS = [Supergraph::LOCATION].freeze
      TYPENAME_NODE = GraphQL::Language::Nodes::Field.new(alias: "_STITCH_typename", name: "__typename")

      def initialize(supergraph:, document:)
        @supergraph = supergraph
        @document = document
        @sequence_key = 0
        @operations_by_grouping = {}
      end

      def perform
        build_root_operations
        expand_abstract_boundaries
        self
      end

      def operations
        ops = @operations_by_grouping.values
        ops.sort_by!(&:key)
        ops
      end

      def to_h
        { "ops" => operations.map(&:to_h) }
      end

      private

      def add_operation(location:, parent_type:, selections: nil, insertion_path: [], operation_type: "query", after_key: 0, boundary: nil)
        parent_key = @sequence_key += 1
        selection_set, variables = if selections&.any?
          extract_locale_selections(location, parent_type, selections, insertion_path, parent_key)
        end

        grouping = [after_key, location, parent_type.graphql_name, *insertion_path].join("/")

        if op = @operations_by_grouping[grouping]
          op.selections += selection_set if selection_set
          op.variables.merge!(variables) if variables
          return op
        end

        type_conditional = !parent_type.kind.abstract? && parent_type != @supergraph.schema.query && parent_type != @supergraph.schema.mutation

        @operations_by_grouping[grouping] = PlannerOperation.new(
          key: parent_key,
          after_key: after_key,
          location: location,
          parent_type: parent_type,
          operation_type: operation_type,
          insertion_path: insertion_path,
          type_condition: type_conditional ? parent_type.graphql_name : nil,
          selections: selection_set || [],
          variables: variables || {},
          boundary: boundary,
        )
      end

      def build_root_operations
        case @document.operation.operation_type
        when "query"
          # plan steps grouping all fields by location for async execution
          parent_type = @supergraph.schema.query

          selections_by_location = @document.operation.selections.each_with_object({}) do |node, memo|
            locations = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name] || SUPERGRAPH_LOCATIONS
            memo[locations.last] ||= []
            memo[locations.last] << node
          end

          selections_by_location.each do |location, selections|
            add_operation(location: location, parent_type: parent_type, selections: selections)
          end

        when "mutation"
          # plan steps grouping sequential fields by location for serial execution
          parent_type = @supergraph.schema.mutation
          location_groups = []

          @document.operation.selections.reduce(nil) do |last_location, node|
            location = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name].last
            if location != last_location
              location_groups << {
                location: location,
                selections: [],
              }
            end
            location_groups.last[:selections] << node
            location
          end

          location_groups.reduce(0) do |after_key, group|
            add_operation(
              location: group[:location],
              selections: group[:selections],
              operation_type: "mutation",
              parent_type: parent_type,
              after_key: after_key
            ).key
          end

        else
          raise "Invalid operation type."
        end
      end

      def extract_locale_selections(current_location, parent_type, input_selections, insertion_path, after_key)
        remote_selections = []
        selections_result = []
        variables_result = {}
        implements_fragments = false

        if parent_type.kind.interface?
          # fields of a merged interface may not belong to the interface at the local level,
          # so these non-local interface fields get expanded into typed fragments for planning
          local_interface_fields = @supergraph.fields_by_type_and_location[parent_type.graphql_name][current_location]
          extended_selections = []

          input_selections.reject! do |node|
            if node.is_a?(GraphQL::Language::Nodes::Field) && !local_interface_fields.include?(node.name)
              extended_selections << node
              true
            end
          end

          if extended_selections.any?
            possible_types = Util.get_possible_types(@supergraph.schema, parent_type)
            possible_types.each do |possible_type|
              next if possible_type.kind.abstract? # ignore child interfaces
              next unless @supergraph.locations_by_type[possible_type.graphql_name].include?(current_location)

              type_name = GraphQL::Language::Nodes::TypeName.new(name: possible_type.graphql_name)
              input_selections << GraphQL::Language::Nodes::InlineFragment.new(type: type_name, selections: extended_selections)
            end
          end
        end

        input_selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            if node.name == "__typename"
              selections_result << node
              next
            end

            possible_locations = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name] || SUPERGRAPH_LOCATIONS
            unless possible_locations.include?(current_location)
              remote_selections << node
              next
            end

            field_type = Util.get_named_type_for_field_node(@supergraph.schema, parent_type, node)

            extract_node_variables!(node, variables_result)

            if Util.is_leaf_type?(field_type)
              selections_result << node
            else
              expanded_path = [*insertion_path, node.alias || node.name]
              selection_set, variables = extract_locale_selections(current_location, field_type, node.selections, expanded_path, after_key)
              selections_result << node.merge(selections: selection_set)
              variables_result.merge!(variables)
            end

          when GraphQL::Language::Nodes::InlineFragment
            next unless @supergraph.locations_by_type[node.type.name].include?(current_location)

            fragment_type = @supergraph.schema.types[node.type.name]
            selection_set, variables = extract_locale_selections(current_location, fragment_type, node.selections, insertion_path, after_key)
            selections_result << node.merge(selections: selection_set)
            variables_result.merge!(variables)
            implements_fragments = true

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @document.fragment_definitions[node.name]
            next unless @supergraph.locations_by_type[fragment.type.name].include?(current_location)

            fragment_type = @supergraph.schema.types[fragment.type.name]
            selection_set, variables = extract_locale_selections(current_location, fragment_type, fragment.selections, insertion_path, after_key)
            selections_result << GraphQL::Language::Nodes::InlineFragment.new(type: fragment.type, selections: selection_set)
            variables_result.merge!(variables)
            implements_fragments = true

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end

        if remote_selections.any?
          selection_set = build_child_operations(current_location, parent_type, remote_selections, insertion_path, after_key)
          selections_result.concat(selection_set)
        end

        if parent_type.kind.abstract? || implements_fragments
          selections_result << TYPENAME_NODE
        end

        return selections_result, variables_result
      end

      def build_child_operations(current_location, parent_type, input_selections, insertion_path, after_key)
        parent_selections_result = []
        selections_by_location = {}

        # distribute unique fields among required locations
        input_selections.reject! do |node|
          possible_locations = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name]
          if possible_locations.length == 1
            selections_by_location[possible_locations.first] ||= []
            selections_by_location[possible_locations.first] << node
            true
          end
        end

        # distribute non-unique fields among available locations, preferring used locations
        if input_selections.any?
          # weight locations by number of needed fields available, prefer greater availability
          location_weights = input_selections.each_with_object({}) do |node, memo|
            possible_locations = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name]
            possible_locations.each do |location|
              memo[location] ||= 0
              memo[location] += 1
            end
          end

          input_selections.each do |node|
            possible_locations = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name]

            perfect_location_score = input_selections.length
            preferred_location_score = 0
            preferred_location = possible_locations.reduce(possible_locations.first) do |current_loc, candidate_loc|
              score = selections_by_location[location] ? perfect_location_score : 0
              score += location_weights.fetch(candidate_loc, 0)

              if score > preferred_location_score
                preferred_location_score = score
                candidate_loc
              else
                current_loc
              end
            end

            selections_by_location[preferred_location] ||= []
            selections_by_location[preferred_location] << node
          end
        end

        routes = @supergraph.route_type_to_locations(parent_type.graphql_name, current_location, selections_by_location.keys)
        routes.values.each_with_object({}) do |route, memo|
          route.reduce(nil) do |parent_op, boundary|
            location = boundary["location"]
            next memo[location] if memo[location]

            child_op = memo[location] = add_operation(
              location: location,
              selections: selections_by_location[location],
              parent_type: parent_type,
              insertion_path: insertion_path,
              boundary: boundary,
              after_key: after_key,
            )

            foreign_key_node = GraphQL::Language::Nodes::Field.new(
              alias: "_STITCH_#{boundary["selection"]}",
              name: boundary["selection"]
            )

            if parent_op
              parent_op.selections << foreign_key_node << TYPENAME_NODE
            else
              parent_selections_result << foreign_key_node << TYPENAME_NODE
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
            extract_node_variables!(argument.value, memo)
          when GraphQL::Language::Nodes::VariableIdentifier
            memo[argument.value.name] ||= @document.variable_definitions[argument.value.name]
          end
        end
      end

      # expand concrete type selections into typed fragments when sending to abstract boundaries
      def expand_abstract_boundaries
        @operations_by_grouping.each do |_grouping, op|
          next unless op.boundary

          boundary_type = @supergraph.schema.get_type(op.boundary["type_name"])
          next unless boundary_type.kind.abstract?

          unless op.parent_type == boundary_type
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
        end
      end
    end
  end
end
