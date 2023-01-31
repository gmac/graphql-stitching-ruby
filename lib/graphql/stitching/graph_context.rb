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
        @possible_keys_by_type_and_location = {}
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

      # inverts fields map to provide fields for a type/location
      def fields_by_type_and_location
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

      def possible_keys_for_type_and_location(type_name, location)
        possible_keys_by_type = @possible_keys_by_type_and_location[type_name] ||= {}
        possible_keys_by_type[location] ||= begin
          location_fields = fields_by_type_and_location[type_name][location]
          location_fields & @boundaries[type_name].map { _1["selection"] }
        end
      end

      # For a given type, route from one origin service to one or more remote locations.
      # Tunes a-star search to favor paths with fewest joining locations
      # (ie: favor a longer paths through target locations
      # over a shorter paths with additional locations).
      def route_to_locations(type_name, start_location, goal_locations)
        results = {}
        costs = {}

        paths = possible_keys_for_type_and_location(type_name, start_location).map do |possible_key|
          [{ location: start_location, selection: possible_key, cost: 0 }]
        end

        while paths.any?
          path = paths.pop
          @boundaries[type_name].each do |boundary|
            location = boundary["location"]
            next if path.last[:selection] != boundary["selection"]
            next if path.any? { _1[:location] == location }

            best_cost = costs[location] || Float::INFINITY
            current_cost = path.last[:cost]
            next if best_cost < current_cost

            path << ({ boundary: boundary }.merge!(path.pop))

            if goal_locations.include?(location)
              current_result = results[location]
              if current_result.nil? || current_cost < best_cost || (current_cost == best_cost && path.length < current_result.length)
                results[location] = path.map { _1[:boundary] }
              end
            else
              current_cost = path.last[:cost] += 1
            end

            costs[location] = current_cost if current_cost < best_cost

            possible_keys_for_type_and_location(type_name, location).each do |possible_key|
              paths << [*path, { location: location, selection: possible_key, cost: path.last[:cost] }]
            end
          end

          paths.sort! do |a, b|
            cost_diff = a.last[:cost] - b.last[:cost]
            next cost_diff unless cost_diff.zero?
            a.length - b.length
          end.reverse!
        end

        results
      end
    end
  end
end
