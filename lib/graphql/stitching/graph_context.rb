# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class GraphContext
      attr_reader :schema, :boundaries, :locations_by_type_and_field

      DEFAULT_CLIENT = ->(document, variables, location) { raise "Not implemented." }

      def initialize(schema:, fields:, boundaries:)
        @schema = schema
        @boundaries = boundaries
        @locations_by_type_and_field = fields
        @clients = { DEFAULT_CLIENT => DEFAULT_CLIENT }
      end

      def add_client(location = DEFAULT_CLIENT, &block)
        raise "A client block must be provided." unless block_given?
        @clients[location] = block
      end

      def get_client(location = nil)
        if location
          location_client = @clients[location]
          raise "No client specified for #{location}." unless location_client
          return location_client
        end
        @clients[DEFAULT_CLIENT]
      end

      def delegation_map
        {
          boundaries: @boundaries,
          fields: @locations_by_type_and_field,
        }
      end

      def fields_by_type_and_location
        # invert fields map to provide fields for a type/location
        @fields_by_type_and_location ||= @locations_by_type_and_field.each_with_object({}) do |(type_name, fields), memo|
          memo[type_name] = fields.each_with_object({}) do |(field_name, locations), memo|
            locations.each do |location|
              memo[location] ||= []
              memo[location] << field_name
            end
          end
        end
      end

      def locations_by_type
        @locations_by_type ||= @locations_by_type_and_field.each_with_object({}) do |(type_name, fields), memo|
          memo[type_name] = fields.values.flatten.uniq
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

        location_fields = fields_by_type_and_location[type_name][start_location]
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
                results[location] = path.map { _1["boundary"] }
                costs[location] = cost
                max_cost = cost if cost > max_cost
              end
            end

            location_fields = fields_by_type_and_location[type_name][location]
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
