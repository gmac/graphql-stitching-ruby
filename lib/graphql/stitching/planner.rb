# frozen_string_literal: true

module GraphQL
  module Stitching
    class Planner
      SUPERGRAPH_LOCATIONS = [Supergraph::LOCATION].freeze
      TYPENAME_NODE = GraphQL::Language::Nodes::Field.new(alias: "_STITCH_typename", name: "__typename")
      EMPTY_OBJECT = {}.freeze

      def initialize(supergraph:, request:)
        @supergraph = supergraph
        @request = request
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

      def build_root_operations
        case @request.operation.operation_type
        when "query"
          # plan steps grouping all fields by location for async execution
          parent_type = @supergraph.schema.query

          selections_by_location = @request.operation.selections.each_with_object({}) do |node, memo|
            locations = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name] || SUPERGRAPH_LOCATIONS

            # root fields currently just delegate to the last location that defined them; this should probably be smarter
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

          @request.operation.selections.reduce(nil) do |last_location, node|
            # root fields currently just delegate to the last location that defined them; this should probably be smarter
            next_location = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name].last

            if next_location != last_location
              location_groups << { location: next_location, selections: [] }
            end

            location_groups.last[:selections] << node
            next_location
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

      def add_operation(
        location:,
        parent_type:,
        selections: nil,
        insertion_path: [],
        operation_type: "query",
        after_key: 0,
        boundary: nil
      )
        parent_key = @sequence_key += 1
        locale_variables = {}
        locale_selections = if selections&.any?
          extract_locale_selections(location, parent_type, selections, insertion_path, parent_key, locale_variables)
        else
          []
        end

        # groupings coalesce similar operation parameters into a single operation
        # multiple operations per service may still occur with different insertion points,
        # but those will get query-batched together during execution.
        grouping = String.new
        grouping << after_key.to_s << "/" << location << "/" << parent_type.graphql_name
        grouping = insertion_path.reduce(grouping) do |memo, segment|
          memo << "/" << segment
        end

        if op = @operations_by_grouping[grouping]
          op.selections.concat(locale_selections)
          op.variables.merge!(locale_variables)
          op
        else
          # concrete types that are not root Query/Mutation report themselves as a type condition
          # executor must check the __typename of loaded objects to see if they match subsequent operations
          # this prevents the executor from taking action on unused fragment selections
          type_conditional = !parent_type.kind.abstract? && parent_type != @supergraph.schema.query && parent_type != @supergraph.schema.mutation

          @operations_by_grouping[grouping] = PlannerOperation.new(
            key: parent_key,
            after_key: after_key,
            location: location,
            parent_type: parent_type,
            operation_type: operation_type,
            insertion_path: insertion_path,
            type_condition: type_conditional ? parent_type.graphql_name : nil,
            selections: locale_selections,
            variables: locale_variables,
            boundary: boundary,
          )
        end
      end

      def extract_locale_selections(current_location, parent_type, input_selections, insertion_path, after_key, locale_variables)
        remote_selections = []
        locale_selections = []
        implements_fragments = false

        # fields of a merged interface may not belong to the interface at the local level,
        # so any non-local interface fields get expanded into typed fragments before planning
        if parent_type.kind.interface?
          expland_interface_selections(current_location, parent_type, input_selections)
        end

        input_selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            if node.name == "__typename"
              locale_selections << node
              next
            end

            possible_locations = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name] || SUPERGRAPH_LOCATIONS
            unless possible_locations.include?(current_location)
              remote_selections << node
              next
            end

            field_type = Util.get_named_type_for_field_node(@supergraph.schema, parent_type, node)
            extract_node_variables!(node, locale_variables)

            if Util.is_leaf_type?(field_type)
              locale_selections << node
            else
              insertion_path.push(node.alias || node.name)
              selection_set = extract_locale_selections(current_location, field_type, node.selections, insertion_path, after_key, locale_variables)
              insertion_path.pop

              locale_selections << node.merge(selections: selection_set)
            end

          when GraphQL::Language::Nodes::InlineFragment
            next unless @supergraph.locations_by_type[node.type.name].include?(current_location)

            fragment_type = @supergraph.schema.types[node.type.name]
            selection_set = extract_locale_selections(current_location, fragment_type, node.selections, insertion_path, after_key, locale_variables)
            locale_selections << node.merge(selections: selection_set)
            implements_fragments = true

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions[node.name]
            next unless @supergraph.locations_by_type[fragment.type.name].include?(current_location)

            fragment_type = @supergraph.schema.types[fragment.type.name]
            selection_set = extract_locale_selections(current_location, fragment_type, fragment.selections, insertion_path, after_key, locale_variables)
            locale_selections << GraphQL::Language::Nodes::InlineFragment.new(type: fragment.type, selections: selection_set)
            implements_fragments = true

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end

        if remote_selections.any?
          delegate_remote_selections(
            current_location,
            parent_type,
            locale_selections,
            remote_selections,
            insertion_path,
            after_key
          )
        end

        # always include a __typename on abstracts and types that implement fragments
        # this provides type information to inspect while shaping the final result
        if parent_type.kind.abstract? || implements_fragments
          locale_selections << TYPENAME_NODE
        end

        locale_selections
      end

      def delegate_remote_selections(current_location, parent_type, locale_selections, remote_selections, insertion_path, after_key)
        possible_locations_by_field = @supergraph.locations_by_type_and_field[parent_type.graphql_name]
        selections_by_location = {}

        # distribute unique fields among required locations
        remote_selections.reject! do |node|
          possible_locations = possible_locations_by_field[node.name]
          if possible_locations.length == 1
            selections_by_location[possible_locations.first] ||= []
            selections_by_location[possible_locations.first] << node
            true
          end
        end

        # distribute non-unique fields among available locations, preferring locations already used
        if remote_selections.any?
          # weight locations by number of required fields available, preferring greater availability
          location_weights = if remote_selections.length > 1
            remote_selections.each_with_object({}) do |node, memo|
              possible_locations = possible_locations_by_field[node.name]
              possible_locations.each do |location|
                memo[location] ||= 0
                memo[location] += 1
              end
            end
          else
            EMPTY_OBJECT
          end

          remote_selections.each do |node|
            possible_locations = possible_locations_by_field[node.name]
            preferred_location_score = 0

            # hill climbing selects highest scoring locations to use
            preferred_location = possible_locations.reduce(possible_locations.first) do |best_location, possible_location|
              score = selections_by_location[location] ? remote_selections.length : 0
              score += location_weights.fetch(possible_location, 0)

              if score > preferred_location_score
                preferred_location_score = score
                possible_location
              else
                best_location
              end
            end

            selections_by_location[preferred_location] ||= []
            selections_by_location[preferred_location] << node
          end
        end

        routes = @supergraph.route_type_to_locations(parent_type.graphql_name, current_location, selections_by_location.keys)
        routes.values.each_with_object({}) do |route, ops_by_location|
          route.reduce(nil) do |parent_op, boundary|
            location = boundary["location"]
            next ops_by_location[location] if ops_by_location[location]

            op = ops_by_location[location] = add_operation(
              location: location,
              selections: selections_by_location[location],
              parent_type: parent_type,
              insertion_path: insertion_path.dup,
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
              locale_selections << foreign_key_node << TYPENAME_NODE
            end

            op
          end
        end
      end

      def extract_node_variables!(node_with_args, variables={})
        node_with_args.arguments.each_with_object(variables) do |argument, memo|
          case argument.value
          when GraphQL::Language::Nodes::InputObject
            extract_node_variables!(argument.value, memo)
          when GraphQL::Language::Nodes::VariableIdentifier
            memo[argument.value.name] ||= @request.variable_definitions[argument.value.name]
          end
        end
      end

      def expland_interface_selections(current_location, parent_type, input_selections)
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

      # expand concrete type selections into typed fragments when sending to abstract boundaries
      # this shifts all loose selection fields into a wrapping concrete type fragment
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
