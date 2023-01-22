# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class PlanningStep
      attr_accessor :location, :insertion_path, :selections, :children, :boundary

      def initialize(location:, insertion_path: [], selections: [], children: [], boundary: nil)
        @location = location
        @insertion_path = insertion_path
        @selections = selections
        @children = children
        @boundary = boundary
      end

      def to_h
        op = GraphQL::Language::Nodes::OperationDefinition.new(selections: @selections)
        {
          location: @location,
          boundary: @boundary,
          insertion_path: @insertion_path,
          selections: GraphQL::Language::Printer.new.print(op).gsub(/\s+/, " "),
          children: @children.map(&:to_h),
        }
      end
    end

    class Plan
      attr_reader :steps

      SUPPORTED_OPERATIONS = ["query", "mutation"]

      def initialize(context:, document:, operation_name: nil)
        @document = document

        operations = @document.definitions.select do |d|
          next unless d.is_a?(GraphQL::Language::Nodes::OperationDefinition)
          next unless SUPPORTED_OPERATIONS.include?(d.operation_type)
          operation_name ? d.name == operation_name : true
        end

        if operations.length < 1
          raise operation_name ? "Invalid root operation name." : "No root operation."
        elsif operations.length > 1
          raise "An operation name is required when sending multiple operations."
        end

        @steps = create_root_steps(context, operations[0])
      end

      def document_fragments
        @document_fragments ||= @document.definitions.each_with_object({}) do |d, memo|
          memo[d.name] = d if d.is_a?(GraphQL::Language::Nodes::FragmentDefinition)
        end
      end

      def to_h
        { steps: @steps.map(&:to_h) }
      end

      def create_root_steps(ctx, operation)
        case operation.operation_type
        when "query"
          # plan steps grouping all fields by location for async execution
          parent_type = ctx.schema.query

          selections_by_location = operation.selections.each_with_object({}) do |node, memo|
            location = ctx.locations_by_field[parent_type.graphql_name][node.name].last
            memo[location] ||= []
            memo[location] << node
          end

          selections_by_location.map do |location, selections|
            selection_set, child_steps = extract_selection_sets(ctx, parent_type, selections, [], location)
            PlanningStep.new(
              location: location,
              selections: selection_set,
              children: child_steps
            )
          end

        when "mutation"
          # plan steps grouping sequential fields by location for sync execution
          parent_type = ctx.schema.mutation
          location_groups = []

          operation.selections.reduce(nil) do |last_location, node|
            location = ctx.locations_by_field[parent_type.graphql_name][node.name].last
            if location != last_location
              location_groups << {
                location: location,
                selections: [],
              }
            end
            location_groups.last[:selections] << node
            location
          end

          location_groups.map do |g|
            selection_set, child_steps = extract_selection_sets(ctx, parent_type, g[:selections], [], g[:location])
            PlanningStep.new(
              location: g[:location],
              selections: selection_set,
              children: child_steps
            )
          end

        else
          raise "Invalid operation type."
        end
      end

      def extract_selection_sets(ctx, parent_type, input_selections, insertion_path, current_location)
        selections_result = []
        child_steps_result = []
        remote_selections = []

        input_selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            field_type = Util.get_named_type(parent_type.fields[node.name].type)
            locations = ctx.locations_by_field[parent_type.graphql_name][node.name]

            if locations.exclude?(current_location)
              remote_selections << node
            elsif Util.is_leaf_type?(field_type)
              selections_result << node
            else
              expanded_path = [*insertion_path, node.alias || node.name]
              selection_set, child_steps = extract_selection_sets(ctx, field_type, node.selections, expanded_path, current_location)
              selections_result << node.merge(selections: selection_set)
              child_steps_result.concat(child_steps)
            end

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = ctx.schema.types[node.type.name]
            selection_set, child_steps = extract_selection_sets(ctx, fragment_type, node.selections, insertion_path, current_location)
            selections_result << node.merge(selections: selection_set)
            child_steps_result.concat(child_steps)

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = document_fragments[node.name]
            fragment_type = ctx.schema.types[fragment.type.name]
            selection_set, child_steps = extract_selection_sets(ctx, fragment_type, fragment.selections, insertion_path, current_location)
            selections_result << GraphQL::Language::Nodes::InlineFragment.new(type: fragment.type, selections: selection_set)
            child_steps_result.concat(child_steps)
          end
        end

        if remote_selections.any?
          selection_set, child_steps = create_child_steps(ctx, parent_type, remote_selections, insertion_path, current_location)
          selections_result.concat(selection_set)
          child_steps_result.concat(child_steps)
        end

        return selections_result, child_steps_result
      end

      def create_child_steps(ctx, parent_type, input_selections, insertion_path, current_location)
        parent_selections_result = []
        child_steps_result = []
        selections_by_location = {}

        # distribute unique fields among locations
        input_selections.reject! do |node|
          possible_locations = ctx.locations_by_field[parent_type.graphql_name][node.name]
          if possible_locations.length == 1
            selections_by_location[possible_locations.first] ||= []
            selections_by_location[possible_locations.first] << node
            true
          end
        end

        # distribute non-unique fields among locations
        if input_selections.any?
          location_weights = input_selections.each_with_object({}) do |node, memo|
            possible_locations = ctx.locations_by_field[parent_type.graphql_name][node.name]
            possible_locations.each do |location|
              memo[location] ||= 0
              memo[location] += 1
            end
          end

          input_selections.each do |node|
            possible_locations = ctx.locations_by_field[parent_type.graphql_name][node.name]

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

        routes = route_to_locations(ctx, parent_type, current_location, selections_by_location.keys)
        routes.values.each_with_object({}) do |route, memo|
          route.reduce(nil) do |parent_step, boundary|
            location = boundary["location"]
            next memo[location] if memo[location]

            selections = selections_by_location[location]
            selection_set, child_steps = if selections
              extract_selection_sets(ctx, parent_type, selections, insertion_path, location)
            else
              [[], []]
            end

            child_step = memo[location] = PlanningStep.new(
              location: location,
              insertion_path: insertion_path,
              selections: selection_set,
              children: child_steps,
              boundary: boundary
            )

            foreign_key = GraphQL::Language::Nodes::Field.new(
              alias: "_GQLS_#{boundary["selection"]}",
              name: boundary["selection"]
            )

            if parent_step
              parent_step.selections << foreign_key
              parent_step.children << child_step
            else
              parent_selections_result << foreign_key
              child_steps_result << child_step
            end

            child_step
          end
        end

        return parent_selections_result, child_steps_result
      end

      # For a given type, route from one origin service to many remote locations.
      # Uses A-star, tuned to favor paths with fewest joining locations
      # (this favors a longer path through target locations
      # over a shorter path with additional locations added).
      def route_to_locations(ctx, parent_type, from_location, to_locations)
        boundaries = ctx.boundaries[parent_type.graphql_name]
        possible_keys = boundaries.map { _1["selection"] }
        possible_keys.uniq!

        location_fields = ctx.fields_by_location[parent_type.graphql_name][from_location]
        location_keys = location_fields & possible_keys
        paths = location_keys.map { [{ "location" => from_location, "selection" => _1 }] }

        results = {}
        costs = {}
        max_cost = 1

        while paths.any?
          path = paths.pop
          boundaries.each do |boundary|
            next unless boundary["selection"] == path.last["selection"] && path.none? { boundary["location"] == _1["location"] }

            cost = path.count { to_locations.exclude?(_1["location"]) }
            next if results.length == to_locations.length && cost > max_cost

            path.last["boundary"] = boundary
            location = boundary["location"]
            if to_locations.include?(location)
              result = results[location]
              if result.nil? || cost < costs[location] || (cost == costs[location] && path.length < result.length)
                results[location] = path.map! { _1["boundary"] }
                costs[location] = cost
                max_cost = cost if cost > max_cost
              end
            end

            location_fields = ctx.fields_by_location[parent_type.graphql_name][location]
            location_keys = location_fields & possible_keys
            location_keys.each do |key|
              paths << [*path, { "location" => location, "selection" => key }]
            end
          end

          paths.sort_by!(&:length).reverse!
        end

        results
      end
    end
  end
end
