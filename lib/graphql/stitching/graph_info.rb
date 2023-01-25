# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class GraphInfo
      attr_reader :schema, :locations, :boundaries, :locations_by_field

      def initialize(schema:, locations:, boundaries:, fields:, arguments: {})
        @schema = schema
        @locations = locations
        @boundaries = boundaries
        @locations_by_field = fields
        @locations_by_argument = arguments
      end

      def delegation_map
        {
          locations: @locations,
          boundaries: @boundaries,
          fields: @locations_by_field,
          arguments: @locations_by_argument,
        }
      end

      def fields_by_location
        # invert fields map to provide fields for a type/location
        @fields_by_location ||= locations_by_field.each_with_object({}) do |(typename, fields), memo|
          memo[typename] = fields.each_with_object({}) do |(fieldname, locations), memo|
            locations.each do |location|
              memo[location] ||= []
              memo[location] << fieldname
            end
          end
        end
      end

      # For a given type, route from one origin service to one or more remote locations.
      # Tunes a-star search to favor paths with fewest joining locations
      # (ie: favor a longer paths through target locations
      # over a shorter paths with additional locations).
      def route_to_locations(type_name, start_location, goal_locations)
        boundaries_for_type = boundaries[type_name]
        possible_keys = boundaries_for_type.map { _1["selection"] }
        possible_keys.uniq!

        location_fields = fields_by_location[type_name][start_location]
        location_keys = location_fields & possible_keys
        paths = location_keys.map { [{ "location" => start_location, "selection" => _1 }] }

        results = {}
        costs = {}
        max_cost = 1

        while paths.any?
          path = paths.pop
          boundaries_for_type.each do |boundary|
            next unless boundary["selection"] == path.last["selection"] && path.none? { boundary["location"] == _1["location"] }

            cost = path.count { !goal_locations.include?(_1["location"]) }
            next if results.length == goal_locations.length && cost > max_cost

            path.last["boundary"] = boundary
            location = boundary["location"]
            if goal_locations.include?(location)
              result = results[location]
              if result.nil? || cost < costs[location] || (cost == costs[location] && path.length < result.length)
                results[location] = path.map! { _1["boundary"] }
                costs[location] = cost
                max_cost = cost if cost > max_cost
              end
            end

            location_fields = fields_by_location[type_name][location]
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
