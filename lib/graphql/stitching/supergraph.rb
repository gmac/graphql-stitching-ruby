# frozen_string_literal: true

module GraphQL
  module Stitching
    class Supergraph
      LOCATION = "__super"
      INTROSPECTION_TYPES = [
        "__Schema",
        "__Type",
        "__Field",
        "__Directive",
        "__EnumValue",
        "__InputValue",
        "__TypeKind",
        "__DirectiveLocation",
      ].freeze

      attr_reader :schema, :boundaries, :locations_by_type_and_field, :resources

      def initialize(schema:, fields:, boundaries:, resources: {})
        @schema = schema
        @boundaries = boundaries
        @locations_by_type_and_field = INTROSPECTION_TYPES.each_with_object(fields) do |type_name, memo|
          introspection_type = schema.get_type(type_name)
          next unless introspection_type.kind.fields?

          memo[type_name] = introspection_type.fields.keys.each_with_object({}) do |field_name, m|
            m[field_name] = [LOCATION]
          end
        end

        @possible_keys_by_type_and_location = {}
        @resources = { LOCATION => @schema }.merge!(resources)
      end

      def export
        return GraphQL::Schema::Printer.print_schema(@schema), {
          "fields" => @locations_by_type_and_field.reject { |k, _v| INTROSPECTION_TYPES.include?(k) },
          "boundaries" => @boundaries,
        }
      end

      def self.from_export(schema, delegation_map)
        schema = GraphQL::Schema.from_definition(schema) if schema.is_a?(String)
        new(
          schema: schema,
          fields: delegation_map["fields"],
          boundaries: delegation_map["boundaries"]
        )
      end

      def assign_location_resource(location, schema_or_client = nil, &block)
        schema_or_client ||= block
        unless schema_or_client.is_a?(Class) && schema_or_client <= GraphQL::Schema
          raise "A client or block handler must be provided." unless schema_or_client
          raise "A client must be callable" unless schema_or_client.respond_to?(:call)
        end
        @resources[location] = schema_or_client
      end

      def execute_at_location(location, query, variables)
        resource = resources[location]

        if resource.nil?
          raise "No executable resource assigned for #{location} location."
        elsif resource.is_a?(Class) && resource <= GraphQL::Schema
          resource.execute(
            query: query,
            variables: variables,
            validate: false,
          )
        elsif resource.is_a?(RemoteClient) || resource.respond_to?(:call)
          resource.call(location, query, variables)
        else
          raise "Unexpected executable resource type for #{location} location."
        end
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
          location_fields = fields_by_type_and_location[type_name][location] || []
          location_fields & @boundaries[type_name].map { _1["selection"] }
        end
      end

      # For a given type, route from one origin service to one or more remote locations.
      # Tunes a-star search to favor paths with fewest joining locations, ie:
      # favor longer paths through target locations over shorter paths with additional locations.
      def route_type_to_locations(type_name, start_location, goal_locations)
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
              paths << [*path, { location: location, selection: possible_key, cost: current_cost }]
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
