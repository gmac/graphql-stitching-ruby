# frozen_string_literal: true
# typed: true

require_relative "planner/step"

module GraphQL
  module Stitching
    # Planner partitions request selections by best-fit graph locations,
    # and provides a query plan with sequential execution steps.
    class Planner
      SUPERGRAPH_LOCATIONS = [Supergraph::SUPERGRAPH_LOCATION].freeze
      ROOT_INDEX = 0

      class ScopePartition
        #: Location
        attr_reader :location

        #: Array[SelectionNode]
        attr_reader :selections

        #: (location: Location, selections: Array[SelectionNode]) -> void
        def initialize(location:, selections:)
          @location = location #: Location
          @selections = selections #: Array[SelectionNode]
        end
      end

      #: (Request request) -> void
      def initialize(request)
        @request = request #: Request
        @supergraph = request.supergraph #: Supergraph
        @planning_index = ROOT_INDEX #: Integer
        @steps_by_entrypoint = {} #: Hash[String, Step]
      end

      #: -> Plan
      def perform
        build_root_entrypoints
        expand_abstract_resolvers
        Plan.new(ops: steps.map!(&:to_plan_op))
      end

      #: -> Array[Step]
      def steps
        @steps_by_entrypoint.values.sort_by!(&:index)
      end

      private

      # **
      # Algorithm:
      #
      # A) Group all root selections by their preferred entrypoint locations.
      # A.1) Group query fields by location for parallel execution.
      # A.2) Partition mutation fields by consecutive location for serial execution.
      # A.3) Permit exactly one subscription field.
      #
      # B) Extract contiguous selections for each entrypoint location.
      # B.1) Selections on interface types that do not belong to the interface at the
      #      entrypoint location are expanded into concrete type fragments prior to extraction.
      # B.2) Filter the selection tree down to just fields of the entrypoint location.
      #      Adjoining selections not available here get split off into new entrypoints (C).
      # B.3) Collect all variable definitions used within the filtered selection.
      #      These specify which request variables to pass along with each step.
      # B.4) Add a `__typename` export to abstracts and types that implement fragments.
      #      This provides resolved type information used during execution.
      #
      # C) Delegate adjoining selections to new entrypoint locations.
      # C.1) Distribute unique fields among their required locations.
      # C.2) Distribute non-unique fields among locations that were added during C.1.
      # C.3) Distribute remaining fields among locations weighted by greatest availability.
      #
      # D) Create paths routing to new entrypoint locations via resolver queries.
      # D.1) Types joining through multiple keys route using A* search.
      # D.2) Types joining through a single key route via quick location match.
      # (D.2 is an optional optimization of D.1)
      #
      # E) Translate resolver pathways into new entrypoints.
      # E.1) Add the key of each resolver query into the prior location's selection set.
      # E.2) Add a planner step for each new entrypoint location, then extract it (B).
      #
      # F) Wrap concrete selections targeting abstract resolvers in typed fragments.
      # **

      # adds a planning step for fetching and inserting data into the aggregate result.
      def add_step(
        location:,
        parent_index:,
        parent_type:,
        selections:,
        variables: {},
        path: [],
        operation_type: QUERY_OP,
        resolver: nil
      )
        # coalesce repeat parameters into a single entrypoint
        entrypoint = String.new
        entrypoint << parent_index.to_s << "/" << location << "/" << parent_type.graphql_name
        entrypoint << "/" << (resolver&.key&.to_s || "") << "/#"
        path.each { entrypoint << "/" << _1 }

        step = @steps_by_entrypoint[entrypoint]
        next_index = step ? step.index : @planning_index += 1

        unless selections.empty?
          selections = extract_locale_selections(location, parent_type, next_index, selections, path, variables)
        end

        if step.nil?
          @steps_by_entrypoint[entrypoint] = Step.new(
            index: next_index,
            after: parent_index,
            location: location,
            parent_type: parent_type,
            operation_type: operation_type,
            selections: selections,
            variables: variables,
            path: path,
            resolver: resolver,
          )
        else
          step.variables.merge!(variables)
          step.selections.concat(selections)
          step
        end
      end

      # A) Group all root selections by their preferred entrypoint locations.
      #: -> void
      def build_root_entrypoints
        parent_type = @request.query.root_type_for_operation(@request.operation.operation_type)

        case @request.operation.operation_type
        when QUERY_OP
          # A.1) Group query fields by location for parallel execution.
          selections_by_location = Hash.new { |h, k| h[k] = [] }
          each_field_in_scope(parent_type, @request.operation.selections) do |node|
            locations = locations_for_field(parent_type, node.name)
            selections_by_location[locations.first] << node
          end

          selections_by_location.each do |location, selections|
            add_step(
              location: location,
              parent_index: ROOT_INDEX,
              parent_type: parent_type,
              selections: selections,
              operation_type: QUERY_OP,
            )
          end

        when MUTATION_OP
          # A.2) Partition mutation fields by consecutive location for serial execution.
          partitions = []
          each_field_in_scope(parent_type, @request.operation.selections) do |node|
            locations = locations_for_field(parent_type, node.name)
            next_location = locations.fetch(0)

            if partitions.none? || partitions.fetch(-1).location != next_location
              partitions << ScopePartition.new(location: next_location, selections: [])
            end

            partitions.fetch(-1).selections << node
          end

          partitions.reduce(ROOT_INDEX) do |parent_index, partition|
            add_step(
              location: partition.location,
              parent_index: parent_index,
              parent_type: parent_type,
              selections: partition.selections,
              operation_type: MUTATION_OP,
            ).index
          end

        when SUBSCRIPTION_OP
          # A.3) Permit exactly one subscription field.
          each_field_in_scope(parent_type, @request.operation.selections) do |node|
            raise DocumentError.new("root field") unless @steps_by_entrypoint.empty?

            locations = locations_for_field(parent_type, node.name)
            add_step(
              location: locations.first,
              parent_index: ROOT_INDEX,
              parent_type: parent_type,
              selections: [node],
              operation_type: SUBSCRIPTION_OP,
            )
          end

        else
          raise DocumentError.new("operation type")
        end
      end

      #: (CompositeType parent_type, Array[SelectionNode] input_selections) { (GraphQL::Language::Nodes::Field) -> void } -> void
      def each_field_in_scope(parent_type, input_selections, &block)
        input_selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            yield(node)

          when GraphQL::Language::Nodes::InlineFragment
            next unless node.type.nil? || parent_type.graphql_name == node.type.name
            each_field_in_scope(parent_type, node.selections, &block)

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions[node.name]
            raise DocumentError.new("fragment definition") unless fragment

            next unless parent_type.graphql_name == fragment.type.name
            each_field_in_scope(parent_type, fragment.selections, &block)

          end
        end
      end

      # B) Contiguous selections are extracted for each entrypoint location.
      #: (
      #|   String current_location,
      #|   CompositeType parent_type,
      #|   Integer parent_index,
      #|   Array[SelectionNode] input_selections,
      #|   Array[String] path,
      #|   Variables locale_variables,
      #|   ?Array[SelectionNode] locale_selections
      #| ) -> Array[SelectionNode]
      def extract_locale_selections(
        current_location,
        parent_type,
        parent_index,
        input_selections,
        path,
        locale_variables,
        locale_selections = []
      )
        # B.1) Expand selections on interface types that do not belong to this location.
        input_selections = expand_interface_selections(current_location, parent_type, input_selections)

        # B.2) Filter the selection tree down to just fields of the entrypoint location.
        # Adjoining selections not available here get split off into new entrypoints (C).
        remote_selections = [] #: Array[GraphQL::Language::Nodes::Field]
        requires_typename = parent_type.kind.abstract?

        input_selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            if node.alias&.start_with?(TypeResolver::EXPORT_PREFIX) && node.object_id != TypeResolver::TYPENAME_EXPORT_NODE.object_id
              raise StitchingError, %(Alias "#{node.alias}" is not allowed because "#{TypeResolver::EXPORT_PREFIX}" is a reserved prefix.)
            elsif node.name == TYPENAME
              locale_selections << node
              next
            end

            possible_locations = locations_for_field(parent_type, node.name)
            unless possible_locations.include?(current_location)
              remote_selections << node
              next
            end

            # B.3) Collect all variable definitions used within the filtered selection.
            extract_node_argument_variables(node, locale_variables)
            extract_node_directive_variables(node, locale_variables)
            schema_fields = @supergraph.memoized_schema_fields(parent_type.graphql_name)
            field_type = schema_fields.fetch(node.name).type.unwrap

            if Util.is_leaf_type?(field_type)
              locale_selections << node
            else
              path.push(node.alias || node.name)
              selection_set = extract_locale_selections(current_location, field_type, parent_index, node.selections, path, locale_variables)
              path.pop

              locale_selections << node.merge(selections: selection_set)
            end

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = node.type ? @supergraph.memoized_schema_types.fetch(node.type.name) : parent_type
            next unless locations_for_type(fragment_type.graphql_name).include?(current_location)

            extract_node_directive_variables(node, locale_variables)
            is_same_scope = fragment_type == parent_type && node.directives.empty?
            selection_set = is_same_scope ? locale_selections : []
            extract_locale_selections(current_location, fragment_type, parent_index, node.selections, path, locale_variables, selection_set)

            unless is_same_scope
              locale_selections << node.merge(selections: selection_set)
              requires_typename = true
            end

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions[node.name]
            raise DocumentError.new("fragment definition") unless fragment

            next unless locations_for_type(fragment.type.name).include?(current_location)

            extract_node_directive_variables(node, locale_variables)
            extract_node_directive_variables(fragment, locale_variables)
            requires_typename = true
            fragment_type = @supergraph.memoized_schema_types.fetch(fragment.type.name)
            directives = fragment.directives.empty? && node.directives.empty? ? EMPTY_ARRAY : fragment.directives + node.directives
            is_same_scope = fragment_type == parent_type && directives.empty?
            selection_set = is_same_scope ? locale_selections : []
            extract_locale_selections(current_location, fragment_type, parent_index, fragment.selections, path, locale_variables, selection_set)

            unless is_same_scope
              locale_selections << GraphQL::Language::Nodes::InlineFragment.new(type: fragment.type, directives: directives, selections: selection_set)
            end

          end
        end

        # B.4) Add a `__typename` export to abstracts and types that implement
        # fragments so that resolved type information is available during execution.
        if requires_typename && !locale_selections.include?(TypeResolver::TYPENAME_EXPORT_NODE)
          locale_selections << TypeResolver::TYPENAME_EXPORT_NODE
        end

        if remote_selections.any?
          # C) Delegate adjoining selections to new entrypoint locations.
          remote_selections_by_location = delegate_remote_selections(parent_type, remote_selections)

          # D) Create paths routing to new entrypoint locations via resolver queries.
          routes = @supergraph.route_type_to_locations(parent_type.graphql_name, current_location, remote_selections_by_location.each_key)

          # E) Translate resolver pathways into new entrypoints.
          routes.each_value do |route|
            route.reduce(locale_selections) do |parent_selections, resolver|
              # E.1) Add the key of each resolver query into the prior location's selection set.
              if key = resolver.key
                key.export_nodes.each { parent_selections << _1 }
              end
              parent_selections.uniq! do |node|
                export_node = node.is_a?(GraphQL::Language::Nodes::Field) && TypeResolver.export_key?(node.alias)
                export_node ? node.alias : node.object_id
              end

              # E.2) Add a planner step for each new entrypoint location.
              add_step(
                location: resolver.location,
                parent_index: parent_index,
                parent_type: parent_type,
                selections: remote_selections_by_location[resolver.location] || [],
                path: path.dup,
                resolver: resolver.key ? resolver : nil,
              ).selections
            end
          end
        end

        locale_selections
      end

      # B.1) Selections on interface types that do not belong to the interface at the
      # entrypoint location are expanded into concrete type fragments prior to extraction.
      #: (String current_location, CompositeType parent_type, Array[SelectionNode] input_selections) -> Array[SelectionNode]
      def expand_interface_selections(current_location, parent_type, input_selections)
        return input_selections unless parent_type.kind.interface?

        local_interface_fields = @supergraph.fields_by_type_and_location.fetch(parent_type.graphql_name).fetch(current_location)

        expanded_selections = [] #: Array[SelectionNode]
        input_selections = input_selections.filter_map do |node|
          if node.is_a?(GraphQL::Language::Nodes::Field) && node.name != TYPENAME && !local_interface_fields.include?(node.name)
            expanded_selections << node
            nil
          else
            node
          end
        end

        if expanded_selections.any?
          @request.query.possible_types(parent_type).each do |possible_type|
            next unless locations_for_type(possible_type.graphql_name).include?(current_location)

            type_name = GraphQL::Language::Nodes::TypeName.new(name: possible_type.graphql_name)
            input_selections << GraphQL::Language::Nodes::InlineFragment.new(type: type_name, selections: expanded_selections)
          end
        end

        input_selections
      end

      # B.3) Collect all variable definitions used within the filtered selection.
      # These specify which request variables to pass along with each step.
      #: (ArgumentNode node, Variables variable_definitions) -> void
      def extract_node_argument_variables(node, variable_definitions)
        arguments = node.arguments
        return if arguments.empty?

        arguments.each { |argument| extract_value_variables(argument.value, variable_definitions) }
      end

      #: (SelectionNode node, Variables variable_definitions) -> void
      def extract_node_directive_variables(node, variable_definitions)
        directives = node.directives
        return if directives.empty?

        directives.each { |directive| extract_node_argument_variables(directive, variable_definitions) }
      end

      #: (untyped value, Variables variable_definitions) -> void
      def extract_value_variables(value, variable_definitions)
        case value
        when GraphQL::Language::Nodes::InputObject
          extract_node_argument_variables(value, variable_definitions)
        when GraphQL::Language::Nodes::VariableIdentifier
          variable_definitions[value.name] ||= @request.variable_definitions[value.name]
        when Array
          value.each { extract_value_variables(_1, variable_definitions) }
        end
      end

      # C) Delegate adjoining selections to new entrypoint locations.
      #: (CompositeType parent_type, Array[GraphQL::Language::Nodes::Field] remote_selections) -> Hash[String, Array[GraphQL::Language::Nodes::Field]]
      def delegate_remote_selections(parent_type, remote_selections)
        possible_locations_by_field = @supergraph.locations_by_type_and_field.fetch(parent_type.graphql_name)
        selections_by_location = {}

        # C.1) Distribute unique fields among their required locations.
        remote_selections.reject! do |node|
          possible_locations = possible_locations_by_field.fetch(node.name)
          if possible_locations.length == 1
            selections_by_location[possible_locations.first] ||= []
            selections_by_location[possible_locations.first] << node
            true
          end
        end

        # C.2) Distribute non-unique fields among locations that were added during C.1.
        if !selections_by_location.empty? && !remote_selections.empty?
          available_locations = Set.new(selections_by_location.each_key)

          remote_selections.reject! do |node|
            used_location = possible_locations_by_field.fetch(node.name).find { available_locations.include?(_1) }
            if used_location
              selections_by_location[used_location] << node
              true
            end
          end
        end

        # C.3) Distribute remaining fields among locations weighted by greatest availability.
        if !remote_selections.empty?
          field_count_by_location = Hash.new(0)
          remote_selections.each do |node|
            possible_locations_by_field.fetch(node.name).each do |location|
              field_count_by_location[location] += 1
            end
          end

          remote_selections.each do |node|
            possible_locations = possible_locations_by_field.fetch(node.name)
            preferred_location = possible_locations.max_by { field_count_by_location[_1] } || possible_locations.first
            selections_by_location[preferred_location] ||= []
            selections_by_location[preferred_location] << node
          end
        end

        selections_by_location
      end

      # F) Wrap concrete selections targeting abstract resolvers in typed fragments.
      #: -> void
      def expand_abstract_resolvers
        @steps_by_entrypoint.each_value do |step|
          resolver = step.resolver
          next unless resolver
          resolver_type_name = resolver.type_name
          next unless resolver_type_name

          resolver_type = @supergraph.memoized_schema_types.fetch(resolver_type_name)
          next unless resolver_type.kind.abstract?
          next if resolver_type == step.parent_type

          expanded_selections = [] #: Array[SelectionNode]
          step.selections.reject! do |node|
            if node.is_a?(GraphQL::Language::Nodes::Field)
              expanded_selections << node
              true
            end
          end

          if expanded_selections.any?
            type_name = GraphQL::Language::Nodes::TypeName.new(name: step.parent_type.graphql_name)
            step.selections << GraphQL::Language::Nodes::InlineFragment.new(type: type_name, selections: expanded_selections)
          end
        end
      end

      #: (CompositeType parent_type, FieldName field_name) -> Array[Location]
      def locations_for_field(parent_type, field_name)
        @supergraph.locations_by_type_and_field.fetch(parent_type.graphql_name).fetch(field_name, SUPERGRAPH_LOCATIONS)
      end

      #: (TypeName type_name) -> Array[Location]
      def locations_for_type(type_name)
        @supergraph.locations_by_type.fetch(type_name)
      end
    end
  end
end
