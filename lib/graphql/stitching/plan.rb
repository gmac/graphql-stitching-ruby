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
        document_ops = @document.definitions.select do |d|
          next unless d.is_a?(GraphQL::Language::Nodes::OperationDefinition)
          next unless SUPPORTED_OPERATIONS.include?(d.operation_type)
          @operation_name ? d.name == @operation_name : true
        end

        if document_ops.length < 1
          raise @operation_name ? "Invalid root operation name." : "No root operation."
        elsif document_ops.length > 1
          raise "An operation name is required when sending multiple operations."
        end

        build_root_operations(document_ops.first)
        @operations.reverse!
        self
      end

      def as_json
        { ops: @operations.map(&:as_json) }
      end

      private

      def document_fragments
        @document_fragments ||= @document.definitions.each_with_object({}) do |d, memo|
          memo[d.name] = d if d.is_a?(GraphQL::Language::Nodes::FragmentDefinition)
        end
      end

      def add_operation(location:, operation_type: "query", after_key: nil, boundary: nil, insertion_path: [])
        @sequence_key += 1
        @operations << Operation.new(
          key: @sequence_key,
          after_key: after_key,
          location: location,
          operation_type: operation_type,
          selections: block_given? ? yield(@sequence_key) : [],
          insertion_path: insertion_path,
          boundary: boundary,
        )
        @operations.last
      end

      def build_root_operations(operation)
        case operation.operation_type
        when "query"
          # plan steps grouping all fields by location for async execution
          parent_type = @graph_info.schema.query

          selections_by_location = operation.selections.each_with_object({}) do |node, memo|
            location = @graph_info.locations_by_field[parent_type.graphql_name][node.name].last
            memo[location] ||= []
            memo[location] << node
          end

          selections_by_location.map do |location, selections|
            add_operation(location: location) do |op_id|
              extract_selection_sets(op_id, parent_type, selections, [], location)
            end
          end

        when "mutation"
          # plan steps grouping sequential fields by location for sync execution
          parent_type = @graph_info.schema.mutation
          location_groups = []

          operation.selections.reduce(nil) do |last_location, node|
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

          location_groups.reduce(nil) do |sequence_key, g|
            op = add_operation(location: g[:location], after_key: sequence_key) do |parent_key|
              extract_selection_sets(parent_key, parent_type, g[:selections], [], g[:location])
            end
            op.key
          end

        else
          raise "Invalid operation type."
        end
      end

      def extract_selection_sets(parent_key, parent_type, input_selections, insertion_path, current_location)
        selections_result = []
        remote_selections = []

        input_selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            field_type = Util.get_named_type(parent_type.fields[node.name].type)
            locations = @graph_info.locations_by_field[parent_type.graphql_name][node.name]

            if !locations.include?(current_location)
              remote_selections << node
            elsif Util.is_leaf_type?(field_type)
              selections_result << node
            else
              expanded_path = [*insertion_path, node.alias || node.name]
              selection_set = extract_selection_sets(parent_key, field_type, node.selections, expanded_path, current_location)
              selections_result << node.merge(selections: selection_set)
            end

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = @graph_info.schema.types[node.type.name]
            selection_set = extract_selection_sets(parent_key, fragment_type, node.selections, insertion_path, current_location)
            selections_result << node.merge(selections: selection_set)

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = document_fragments[node.name]
            fragment_type = @graph_info.schema.types[fragment.type.name]
            selection_set = extract_selection_sets(parent_key, fragment_type, fragment.selections, insertion_path, current_location)
            selections_result << GraphQL::Language::Nodes::InlineFragment.new(type: fragment.type, selections: selection_set)
          end
        end

        if remote_selections.any?
          selection_set = build_child_operations(parent_key, parent_type, remote_selections, insertion_path, current_location)
          selections_result.concat(selection_set)
        end

        selections_result
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
              insertion_path: insertion_path,
              boundary: boundary
            ) do |parent_key|
              if selections
                extract_selection_sets(parent_key, parent_type, selections, insertion_path, location)
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
    end
  end
end
