# frozen_string_literal: true

module GraphQL
  module Stitching
    class Planner
      SUPERGRAPH_LOCATIONS = [Supergraph::LOCATION].freeze
      TYPENAME_NODE = GraphQL::Language::Nodes::Field.new(alias: "_STITCH_typename", name: "__typename")

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
        @operations_by_grouping.values.sort_by!(&:key)
      end

      def to_h
        { "ops" => operations.map!(&:to_h) }
      end

      private

      # groups root fields by operational strategy:
      # - query immedaitely groups all root fields by location for async resolution
      # - mutation groups sequential root fields by location for serial resolution
      def build_root_operations
        case @request.operation.operation_type
        when "query"
          parent_type = @supergraph.schema.query

          selections_by_location = {}
          each_selection_in_type(parent_type, @request.operation.selections) do |node|
            locations = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name] || SUPERGRAPH_LOCATIONS
            selections_by_location[locations.first] ||= []
            selections_by_location[locations.first] << node
          end

          selections_by_location.each do |location, selections|
            add_operation(location: location, parent_type: parent_type, selections: selections)
          end

        when "mutation"
          parent_type = @supergraph.schema.mutation

          location_groups = []
          each_selection_in_type(parent_type, @request.operation.selections) do |node|
            next_location = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name].first

            if location_groups.none? || location_groups.last[:location] != next_location
              location_groups << { location: next_location, selections: [] }
            end

            location_groups.last[:selections] << node
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

      def each_selection_in_type(parent_type, input_selections, &block)
        input_selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            yield(node)

          when GraphQL::Language::Nodes::InlineFragment
            next unless parent_type.graphql_name == node.type.name
            each_selection_in_type(parent_type, node.selections, &block)

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions[node.name]
            next unless parent_type.graphql_name == fragment.type.name
            each_selection_in_type(parent_type, fragment.selections, &block)

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end
      end

      # adds an operation (data access) to the plan which maps a data selection to an insertion point.
      # note that planned operations are NOT always 1:1 with executed requests, as the executor can
      # frequently batch different insertion points with the same location into a single request.
      def add_operation(
        location:,
        parent_type:,
        selections:,
        insertion_path: [],
        operation_type: "query",
        after_key: 0,
        boundary: nil
      )
        parent_key = @sequence_key += 1
        locale_variables = {}
        locale_selections = if selections.any?
          extract_locale_selections(location, parent_type, selections, insertion_path, parent_key, locale_variables)
        else
          selections
        end

        # groupings coalesce similar operation parameters into a single operation
        # multiple operations per service may still occur with different insertion points,
        # but those will get query-batched together during execution.
        grouping = String.new("#{after_key}/#{location}/#{parent_type.graphql_name}")
        insertion_path.each { grouping << "/#{_1}" }

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

      # extracts a selection tree that can all be fulfilled through the current planning location.
      # adjoining remote selections will fork new insertion points and extract selections at those locations.
      def extract_locale_selections(current_location, parent_type, input_selections, insertion_path, after_key, locale_variables)
        remote_selections = nil
        locale_selections = []
        implements_fragments = false

        if parent_type.kind.interface?
          input_selections = expand_interface_selections(current_location, parent_type, input_selections)
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
              remote_selections ||= []
              remote_selections << node
              next
            end

            field_type = @supergraph.cached_fields_for_schema_type(parent_type.graphql_name)[node.name].type.unwrap
            extract_node_variables(node, locale_variables)

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

            fragment_type = @supergraph.cached_schema_types[node.type.name]
            selection_set = extract_locale_selections(current_location, fragment_type, node.selections, insertion_path, after_key, locale_variables)
            locale_selections << node.merge(selections: selection_set)
            implements_fragments = true

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions[node.name]
            next unless @supergraph.locations_by_type[fragment.type.name].include?(current_location)

            fragment_type = @supergraph.cached_schema_types[fragment.type.name]
            selection_set = extract_locale_selections(current_location, fragment_type, fragment.selections, insertion_path, after_key, locale_variables)
            locale_selections << GraphQL::Language::Nodes::InlineFragment.new(type: fragment.type, selections: selection_set)
            implements_fragments = true

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end

        if remote_selections
          delegate_remote_selections(
            current_location,
            parent_type,
            locale_selections,
            remote_selections,
            insertion_path,
            after_key
          )
        end

        # always include a __typename on abstracts and scopes that implement fragments
        # this provides type information to inspect while shaping the final result
        if parent_type.kind.abstract? || implements_fragments
          locale_selections << TYPENAME_NODE
        end

        locale_selections
      end

      # distributes remote selections across locations,
      # while spawning new operations for each new fulfillment.
      def delegate_remote_selections(current_location, parent_type, locale_selections, remote_selections, insertion_path, after_key)
        possible_locations_by_field = @supergraph.locations_by_type_and_field[parent_type.graphql_name]
        selections_by_location = {}

        # 1. distribute unique fields among required locations
        remote_selections.reject! do |node|
          possible_locations = possible_locations_by_field[node.name]
          if possible_locations.length == 1
            selections_by_location[possible_locations.first] ||= []
            selections_by_location[possible_locations.first] << node
            true
          end
        end

        # 2. distribute non-unique fields among locations that are already used
        if selections_by_location.any? && remote_selections.any?
          remote_selections.reject! do |node|
            used_location = possible_locations_by_field[node.name].find { selections_by_location[_1] }
            if used_location
              selections_by_location[used_location] << node
              true
            end
          end
        end

        # 3. distribute remaining fields among locations weighted by greatest availability
        if remote_selections.any?
          field_count_by_location = if remote_selections.length > 1
            remote_selections.each_with_object({}) do |node, memo|
              possible_locations_by_field[node.name].each do |location|
                memo[location] ||= 0
                memo[location] += 1
              end
            end
          else
            GraphQL::Stitching::EMPTY_OBJECT
          end

          remote_selections.each do |node|
            possible_locations = possible_locations_by_field[node.name]
            preferred_location = possible_locations.first

            possible_locations.reduce(0) do |max_availability, possible_location|
              available_fields = field_count_by_location.fetch(possible_location, 0)

              if available_fields > max_availability
                preferred_location = possible_location
                available_fields
              else
                max_availability
              end
            end

            selections_by_location[preferred_location] ||= []
            selections_by_location[preferred_location] << node
          end
        end

        # route from current location to target locations via boundary queries,
        # then translate those routes into planner operations
        routes = @supergraph.route_type_to_locations(parent_type.graphql_name, current_location, selections_by_location.keys)
        routes.values.each_with_object({}) do |route, ops_by_location|
          route.reduce(nil) do |parent_op, boundary|
            location = boundary["location"]

            unless op = ops_by_location[location]
              op = ops_by_location[location] = add_operation(
                location: location,
                # routing locations added as intermediaries have no initial selections,
                # but will be given foreign keys by subsequent operations
                selections: selections_by_location[location] || [],
                parent_type: parent_type,
                insertion_path: insertion_path.dup,
                boundary: boundary,
                after_key: after_key,
              )
            end

            foreign_key = "_STITCH_#{boundary["selection"]}"
            parent_selections = parent_op ? parent_op.selections : locale_selections

            if parent_selections.none? { _1.is_a?(GraphQL::Language::Nodes::Field) && _1.alias == foreign_key }
              foreign_key_node = GraphQL::Language::Nodes::Field.new(alias: foreign_key, name: boundary["selection"])
              parent_selections << foreign_key_node << TYPENAME_NODE
            end

            op
          end
        end
      end

      # extracts variable definitions used by a node
      # (each operation tracks the specific variables used in its tree)
      def extract_node_variables(node_with_args, variable_definitions)
        node_with_args.arguments.each do |argument|
          case argument.value
          when GraphQL::Language::Nodes::InputObject
            extract_node_variables(argument.value, variable_definitions)
          when GraphQL::Language::Nodes::VariableIdentifier
            variable_definitions[argument.value.name] ||= @request.variable_definitions[argument.value.name]
          end
        end

        if node_with_args.respond_to?(:directives)
          node_with_args.directives.each do |directive|
            extract_node_variables(directive, variable_definitions)
          end
        end
      end

      # fields of a merged interface may not belong to the interface at the local level,
      # so any non-local interface fields get expanded into typed fragments before planning
      def expand_interface_selections(current_location, parent_type, input_selections)
        local_interface_fields = @supergraph.fields_by_type_and_location[parent_type.graphql_name][current_location]

        expanded_selections = nil
        input_selections = input_selections.reject do |node|
          if node.is_a?(GraphQL::Language::Nodes::Field) && node.name != "__typename" && !local_interface_fields.include?(node.name)
            expanded_selections ||= []
            expanded_selections << node
            true
          end
        end

        if expanded_selections
          @supergraph.schema.possible_types(parent_type).each do |possible_type|
            next unless @supergraph.locations_by_type[possible_type.graphql_name].include?(current_location)

            type_name = GraphQL::Language::Nodes::TypeName.new(name: possible_type.graphql_name)
            input_selections << GraphQL::Language::Nodes::InlineFragment.new(type: type_name, selections: expanded_selections)
          end
        end

        input_selections
      end

      # expand concrete type selections into typed fragments when sending to abstract boundaries
      # this shifts all loose selection fields into a wrapping concrete type fragment
      def expand_abstract_boundaries
        @operations_by_grouping.each do |_grouping, op|
          next unless op.boundary

          boundary_type = @supergraph.cached_schema_types[op.boundary["type_name"]]
          next unless boundary_type.kind.abstract?
          next if boundary_type == op.parent_type

          expanded_selections = nil
          op.selections.reject! do |node|
            if node.is_a?(GraphQL::Language::Nodes::Field)
              expanded_selections ||= []
              expanded_selections << node
              true
            end
          end

          if expanded_selections
            type_name = GraphQL::Language::Nodes::TypeName.new(name: op.parent_type.graphql_name)
            op.selections << GraphQL::Language::Nodes::InlineFragment.new(type: type_name, selections: expanded_selections)
          end
        end
      end
    end
  end
end
