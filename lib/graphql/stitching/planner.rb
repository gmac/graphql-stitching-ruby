# frozen_string_literal: true

module GraphQL
  module Stitching
    class Planner
      SUPERGRAPH_LOCATIONS = [Supergraph::LOCATION].freeze
      QUERY_OP = "query"
      MUTATION_OP = "mutation"
      DEFER_DIRECTIVE = "defer"
      DEFER_LABEL_ARG = "label"
      ROOT_INDEX = 0

      def initialize(supergraph:, request:)
        @supergraph = supergraph
        @request = request
        @planning_index = ROOT_INDEX
        @steps_by_entrypoint = {}
      end

      def perform
        build_root_entrypoints
        expand_abstract_boundaries
        Plan.new(ops: steps.map(&:to_plan_op))
      end

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
      #
      # B) Extract contiguous selections for each entrypoint location.
      #
      # B.1) Selections on interface types that do not belong to the interface at the
      # entrypoint location are expanded into concrete type fragments prior to extraction.
      #
      # B.2) Filter the selection tree down to just fields of the entrypoint location.
      # Adjoining selections not available here get split off into new entrypoints (C).
      #
      # B.3) Collect all variable definitions used within the filtered selection.
      # These specify which request variables to pass along with the selection.
      #
      # B.4) Add a `__typename` selection to abstracts, deferred, and concrete types that
      # implement fragments. This provides resolved type information used during execution.
      #
      # B.5) Add a hint key for returning to the current location in scopes with
      # deferred selections.
      #
      # C) Delegate adjoining selections to new entrypoint locations.
      # C.1) Distribute unique fields among their required locations.
      # C.2) Distribute non-unique fields among locations that were added during C.1.
      # C.3) Distribute remaining fields among locations weighted by greatest availability.
      #
      # D) Create paths routing to new entrypoint locations via boundary queries.
      # D.1) Types joining through multiple keys route using A* search.
      # D.2) Types joining through a single key route via quick location match.
      # (D.2 is an optional optimization of D.1)
      #
      # E) Translate boundary pathways into new planning steps.
      # E.1) Add the key of each boundary query into the prior location's selection set.
      # E.2) Add a planning step for each new entrypoint location, then extract it (B).
      #
      # F) Resolver deferred selections
      #
      # G) Wrap concrete selections targeting abstract boundaries in typed fragments.
      # **

      # adds a planning step for fetching and inserting data into the aggregate result.
      def add_step(
        location:,
        parent_index:,
        parent_type:,
        selections:,
        variables: {},
        path: [],
        defer_label: nil,
        operation_type: QUERY_OP,
        boundary: nil
      )
        # coalesce repeat parameters into a single entrypoint
        boundary_key = boundary ? boundary.key : "_"
        entrypoint = String.new("#{parent_index}/#{location}/#{parent_type.graphql_name}/#{boundary_key}/#{defer_label}")
        path.each { entrypoint << "/#{_1}" }

        step = @steps_by_entrypoint[entrypoint]
        next_index = step ? parent_index : @planning_index += 1

        if selections.any?
          selections = extract_locale_selections(location, parent_type, next_index, selections, path, variables)
        end

        if step.nil?
          # concrete types that are not root Query/Mutation report themselves as a type condition
          # executor must check the __typename of loaded objects to see if they match subsequent operations
          # this prevents the executor from taking action on unused fragment selections
          conditional = !parent_type.kind.abstract? && parent_type != @supergraph.schema.root_type_for_operation(operation_type)

          @steps_by_entrypoint[entrypoint] = PlannerStep.new(
            index: next_index,
            after: parent_index,
            location: location,
            parent_type: parent_type,
            operation_type: operation_type,
            selections: selections,
            variables: variables,
            path: path,
            if_type: conditional ? parent_type.graphql_name : nil,
            boundary: boundary,
            defer_label: defer_label,
          )
        else
          step.selections.concat(selections)
          step
        end
      end

      ScopePartition = Struct.new(:location, :defer_label, :selections, keyword_init: true)

      # A) Group all root selections by their preferred entrypoint locations.
      def build_root_entrypoints
        case @request.operation.operation_type
        when QUERY_OP
          # A.1) Group query fields by location for parallel execution.
          parent_type = @supergraph.schema.query

          selections_by_label_location = {}
          each_field_in_scope(parent_type, @request.operation.selections) do |node, defer_label|
            locations = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name] || SUPERGRAPH_LOCATIONS

            selections_by_label_location[defer_label] ||= {}
            selections_by_label_location[defer_label][locations.first] ||= []
            selections_by_label_location[defer_label][locations.first] << node
          end

          selections_by_label_location.each do |defer_label, selections_by_location|
            selections_by_location.each do |location, selections|
              add_step(
                location: location,
                parent_index: ROOT_INDEX,
                parent_type: parent_type,
                selections: selections,
                defer_label: defer_label,
              )
            end
          end

        when MUTATION_OP
          # A.2) Partition mutation fields by consecutive location for serial execution.
          parent_type = @supergraph.schema.mutation
          base_partitions = []
          defer_partitions = []

          each_field_in_scope(parent_type, @request.operation.selections) do |node, defer_label|
            next_location = @supergraph.locations_by_type_and_field[parent_type.graphql_name][node.name].first

            if defer_label && (defer_partitions.none? || defer_partitions.last.location != next_location || defer_partitions.last.defer_label != defer_label)
              defer_partitions << ScopePartition.new(location: next_location, defer_label: defer_label, selections: [])
            elsif base_partitions.none? || base_partitions.last.location != next_location
              base_partitions << ScopePartition.new(location: next_location, selections: [])
            end

            if defer_label
              defer_partitions.last.selections << node
            else
              base_partitions.last.selections << node
            end
          end

          last_mutation = base_partitions.concat(defer_partitions).reduce(ROOT_INDEX) do |parent_index, partition|
            add_step(
              location: partition.location,
              parent_index: parent_index,
              parent_type: parent_type,
              selections: partition.selections,
              defer_label: partition.defer_label,
              operation_type: MUTATION_OP,
            ).index
          end

          sequence_defer_queries_after(last_mutation)

        else
          raise "Invalid operation type."
        end
      end

      def each_field_in_scope(parent_type, input_selections, defer_label: nil, &block)
        input_selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            yield(node, defer_label)

          when GraphQL::Language::Nodes::InlineFragment
            next unless node.type.nil? || parent_type.graphql_name == node.type.name
            label = extract_defer_label(parent_type, node)
            each_field_in_scope(parent_type, node.selections, defer_label: label, &block)

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions[node.name]
            next unless parent_type.graphql_name == fragment.type.name
            each_field_in_scope(parent_type, fragment.selections, &block)

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end
      end

      # sequence the root of each deferred query after a given step; used to shift
      # deferred selections past mutations steps where they will access mutated state.
      def sequence_defer_queries_after(step_index)
        deferred_query_steps = @steps_by_entrypoint.values.select! { _1.defer_label && _1.operation_type == QUERY_OP }
        return unless deferred_query_steps.any?

        # sorts deferred queries by [label, after] (which should be implicit?)
        deferred_query_steps.sort! do |a, b|
          label_diff = a.defer_label.casecmp(b.defer_label)
          label_diff.zero? ? a.after - b.after : label_diff
        end

        prev_label = nil
        prev_index = nil

        # sequence the root of each deferred query after the last mutation step
        deferred_query_steps.each do |step|
          if step.defer_label != prev_label || step.after == prev_index
            prev_label = step.defer_label
            prev_index = step.after
            step.after = step_index
          end
        end
      end

      # B) Contiguous selections are extracted for each entrypoint location.
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
        remote_selections = nil
        defer_selections = nil
        requires_typename = parent_type.kind.abstract?

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

            # B.3) Collect all variable definitions used within the filtered selection.
            extract_node_variables(node, locale_variables)
            field_type = @supergraph.memoized_schema_fields(parent_type.graphql_name)[node.name].type.unwrap

            if Util.is_leaf_type?(field_type)
              locale_selections << node
            else
              path.push(node.alias || node.name)
              selection_set = extract_locale_selections(current_location, field_type, parent_index, node.selections, path, locale_variables)
              path.pop

              locale_selections << node.merge(selections: selection_set)
            end

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = node.type ? @supergraph.memoized_schema_types[node.type.name] : parent_type
            next unless @supergraph.locations_by_type[fragment_type.graphql_name].include?(current_location)

            if defer_label = extract_defer_label(fragment_type, node)
              defer_selections ||= {}
              defer_selections[defer_label] = node.selections
              next
            end

            is_same_scope = fragment_type == parent_type
            selection_set = is_same_scope ? locale_selections : []
            extract_locale_selections(current_location, fragment_type, parent_index, node.selections, path, locale_variables, selection_set)

            unless is_same_scope
              locale_selections << node.merge(selections: selection_set)
              requires_typename = true
            end

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions[node.name]
            next unless @supergraph.locations_by_type[fragment.type.name].include?(current_location)

            fragment_type = @supergraph.memoized_schema_types[fragment.type.name]
            is_same_scope = fragment_type == parent_type
            selection_set = is_same_scope ? locale_selections : []
            extract_locale_selections(current_location, fragment_type, parent_index, fragment.selections, path, locale_variables, selection_set)

            unless is_same_scope
              locale_selections << GraphQL::Language::Nodes::InlineFragment.new(type: fragment.type, selections: selection_set)
              requires_typename = true
            end

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end

        # B.4) Add a `__typename` selection to abstracts, deferred, and concrete types that
        # implement fragments so that resolved type information is available during execution.
        if requires_typename || defer_selections
          locale_selections << SelectionHint.typename_node
        end

        if remote_selections
          # C) Delegate adjoining selections to new entrypoint locations.
          remote_selections_by_location = delegate_remote_selections(parent_type, remote_selections)

          # D) Create paths routing to new entrypoint locations via boundary queries.
          routes = @supergraph.route_type_to_locations(parent_type.graphql_name, current_location, remote_selections_by_location.keys)

          # E) Translate boundary pathways into new entrypoints.
          routes.each_value do |route|
            route.reduce(locale_selections) do |parent_selections, boundary|
              # E.1) Add the key of each boundary query into the prior location's selection set.
              foreign_key = SelectionHint.key(boundary.key)
              has_key = false
              has_typename = false

              parent_selections.each do |node|
                next unless node.is_a?(GraphQL::Language::Nodes::Field)
                has_key ||= node.alias == foreign_key
                has_typename ||= node.alias == SelectionHint.typename_node.alias
              end

              parent_selections << SelectionHint.key_node(boundary.key) unless has_key
              parent_selections << SelectionHint.typename_node unless has_typename

              # E.2) Add a planner operation for each new entrypoint location.
              location = boundary.location
              add_step(
                location: location,
                parent_index: parent_index,
                parent_type: parent_type,
                selections: remote_selections_by_location[location] || [],
                path: path.dup,
                boundary: boundary,
              ).selections
            end
          end
        end

        if defer_selections
          # F) Build deferred steps.
          defer_selections.each do |label, selections|
            # F.1) Plan a separate step in the current location for each deferred selection scope.
            deferred_step = add_step(
              location: current_location,
              parent_index: parent_index,
              parent_type: parent_type,
              selections: selections,
              path: path.dup,
              boundary: @supergraph.boundary_for_location(parent_type.graphql_name, current_location),
              defer_label: label,
            )

            # F.2) Hoist all deferred selection hints up to the base scope.
            deferred_step.selections.reject! do |node|
              if node.is_a?(GraphQL::Language::Nodes::Field) && SelectionHint.key?(node.alias)
                locale_selections << node
                true
              end
            end

            @steps_by_entrypoint.reject! do |_entrypoint, step|
              # F.3) Eliminate the deferred root step if now empty (ie: contained only hints).
              # Otherwise, add a current location hint to the base scope for deferred return.
              if step.index == deferred_step.index
                next true if deferred_step.selections.none?

                boundary = @supergraph.boundary_for_location(parent_type.graphql_name, current_location)
                locale_selections << SelectionHint.key_node(boundary.key)

              # F.4) Connect all deferred child steps directly to the base scope,
              # and give them the same deferred label identity.
              elsif step.after == deferred_step.index
                step.after = deferred_step.after
                step.defer_label = deferred_step.defer_label
              end
              false
            end
          end

          locale_selections.uniq! do |node|
            next node.alias if node.is_a?(GraphQL::Language::Nodes::Field) && SelectionHint.key?(node.alias)
            node.object_id
          end
        end

        locale_selections
      end

      # B.1) Selections on interface types that do not belong to the interface at the
      # entrypoint location are expanded into concrete type fragments prior to extraction.
      def expand_interface_selections(current_location, parent_type, input_selections)
        return input_selections unless parent_type.kind.interface?

        local_interface_fields = @supergraph.fields_by_type_and_location[parent_type.graphql_name][current_location]

        expanded_selections = nil
        input_selections = input_selections.filter_map do |node|
          if node.is_a?(GraphQL::Language::Nodes::Field) && node.name != "__typename" && !local_interface_fields.include?(node.name)
            expanded_selections ||= []
            expanded_selections << node
            nil
          else
            node
          end
        end

        if expanded_selections
          @supergraph.memoized_schema_possible_types(parent_type.graphql_name).each do |possible_type|
            next unless @supergraph.locations_by_type[possible_type.graphql_name].include?(current_location)

            type_name = GraphQL::Language::Nodes::TypeName.new(name: possible_type.graphql_name)
            input_selections << GraphQL::Language::Nodes::InlineFragment.new(type: type_name, selections: expanded_selections)
          end
        end

        input_selections
      end

      # B.3) Collect all variable definitions used within the filtered selection.
      # These specify which request variables to pass along with the selection.
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

      # C) Delegate adjoining selections to new entrypoint locations.
      def delegate_remote_selections(parent_type, remote_selections)
        possible_locations_by_field = @supergraph.locations_by_type_and_field[parent_type.graphql_name]
        selections_by_location = {}

        # C.1) Distribute unique fields among their required locations.
        remote_selections.reject! do |node|
          possible_locations = possible_locations_by_field[node.name]
          if possible_locations.length == 1
            selections_by_location[possible_locations.first] ||= []
            selections_by_location[possible_locations.first] << node
            true
          end
        end

        # C.2) Distribute non-unique fields among locations that were added during C.1.
        if selections_by_location.any? && remote_selections.any?
          remote_selections.reject! do |node|
            used_location = possible_locations_by_field[node.name].find { selections_by_location[_1] }
            if used_location
              selections_by_location[used_location] << node
              true
            end
          end
        end

        # C.3) Distribute remaining fields among locations weighted by greatest availability.
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

        selections_by_location
      end

      # G) Wrap concrete selections targeting abstract boundaries in typed fragments.
      def expand_abstract_boundaries
        @steps_by_entrypoint.each_value do |op|
          next unless op.boundary

          boundary_type = @supergraph.memoized_schema_types[op.boundary.type_name]
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

      def extract_defer_label(fragment_type, node)
        return nil if node.type || node.directives.none?

        defer = node.directives.find { _1.name == DEFER_DIRECTIVE }
        if defer && @supergraph.deferrable_type?(fragment_type.graphql_name)
          defer.arguments.find { _1.name == DEFER_LABEL_ARG }&.value || SelectionHint.key(DEFER_DIRECTIVE)
        end
      end
    end
  end
end
