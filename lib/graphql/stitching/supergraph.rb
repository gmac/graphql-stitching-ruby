# frozen_string_literal: true

module GraphQL
  module Stitching
    class Supergraph
      LOCATION = "__super"

      def self.validate_executable!(location, executable)
        return true if executable.is_a?(Class) && executable <= GraphQL::Schema
        return true if executable && executable.respond_to?(:call)
        raise StitchingError, "Invalid executable provided for location `#{location}`."
      end

      def self.from_export(schema:, delegation_map:, executables:)
        schema = GraphQL::Schema.from_definition(schema) if schema.is_a?(String)

        executables = delegation_map["locations"].each_with_object({}) do |location, memo|
          executable = executables[location] || executables[location.to_sym]
          if validate_executable!(location, executable)
            memo[location] = executable
          end
        end

        new(
          schema: schema,
          fields: delegation_map["fields"],
          boundaries: delegation_map["boundaries"],
          executables: executables,
        )
      end

      attr_reader :schema, :boundaries, :locations_by_type_and_field, :executables

      def initialize(schema:, fields:, boundaries:, executables:)
        @schema = schema
        @boundaries = boundaries
        @possible_keys_by_type = {}
        @possible_keys_by_type_and_location = {}
        @memoized_schema_possible_types = {}
        @memoized_schema_fields = {}

        # add introspection types into the fields mapping
        @locations_by_type_and_field = memoized_introspection_types.each_with_object(fields) do |(type_name, type), memo|
          next unless type.kind.fields?

          memo[type_name] = type.fields.keys.each_with_object({}) do |field_name, m|
            m[field_name] = [LOCATION]
          end
        end.freeze

        # validate and normalize executable references
        @executables = executables.each_with_object({ LOCATION => @schema }) do |(location, executable), memo|
          if self.class.validate_executable!(location, executable)
            memo[location.to_s] = executable
          end
        end.freeze
      end

      def fields
        @locations_by_type_and_field.reject { |k, _v| memoized_introspection_types[k] }
      end

      def locations
        @executables.keys.reject { _1 == LOCATION }
      end

      def export
        return GraphQL::Schema::Printer.print_schema(@schema), {
          "locations" => locations,
          "fields" => fields,
          "boundaries" => @boundaries,
        }
      end

      def memoized_introspection_types
        @memoized_introspection_types ||= schema.introspection_system.types
      end

      def memoized_schema_types
        @memoized_schema_types ||= @schema.types
      end

      def memoized_schema_possible_types(type_name)
        @memoized_schema_possible_types[type_name] ||= @schema.possible_types(memoized_schema_types[type_name])
      end

      def memoized_schema_fields(type_name)
        @memoized_schema_fields[type_name] ||= begin
          fields = memoized_schema_types[type_name].fields
          @schema.introspection_system.dynamic_fields.each do |field|
            fields[field.name] ||= field # adds __typename
          end

          if type_name == @schema.query.graphql_name
            @schema.introspection_system.entry_points.each do |field|
              fields[field.name] ||= field # adds __schema, __type
            end
          end

          fields
        end
      end

      def execute_at_location(location, source, variables, context)
        executable = executables[location]

        if executable.nil?
          raise StitchingError, "No executable assigned for #{location} location."
        elsif executable.is_a?(Class) && executable <= GraphQL::Schema
          executable.execute(
            query: source,
            variables: variables,
            context: context.frozen? ? context.dup : context,
            validate: false,
          )
        elsif executable.respond_to?(:call)
          executable.call(location, source, variables, context)
        else
          raise StitchingError, "Missing valid executable for #{location} location."
        end
      end

      # inverts fields map to provide fields for a type/location
      # "Type" => "location" => ["field1", "field2", ...]
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

      # "Type" => ["location1", "location2", ...]
      def locations_by_type
        @locations_by_type ||= @locations_by_type_and_field.each_with_object({}) do |(type_name, fields), memo|
          memo[type_name] = fields.values.flatten.uniq
        end
      end

      # collects all possible boundary keys for a given type
      # ("Type") => ["id", ...]
      def possible_keys_for_type(type_name)
        @possible_keys_by_type[type_name] ||= begin
          @boundaries[type_name].map { _1["key"] }.tap(&:uniq!)
        end
      end

      # collects possible boundary keys for a given type and location
      # ("Type", "location") => ["id", ...]
      def possible_keys_for_type_and_location(type_name, location)
        possible_keys_by_type = @possible_keys_by_type_and_location[type_name] ||= {}
        possible_keys_by_type[location] ||= begin
          location_fields = fields_by_type_and_location[type_name][location] || []
          location_fields & possible_keys_for_type(type_name)
        end
      end

      # For a given type, route from one origin location to one or more remote locations
      # used to connect a partial type across locations via boundary queries
      def route_type_to_locations(type_name, start_location, goal_locations)
        if possible_keys_for_type(type_name).length > 1
          # multiple keys use an a-star search to traverse intermediary locations
          return route_type_to_locations_via_search(type_name, start_location, goal_locations)
        end

        # types with a single key attribute must all be within a single hop of each other,
        # so can use a simple match to collect boundaries for the goal locations.
        @boundaries[type_name].each_with_object({}) do |boundary, memo|
          if goal_locations.include?(boundary["location"])
            memo[boundary["location"]] = [boundary]
          end
        end
      end

      private

      # tunes a-star search to favor paths with fewest joining locations, ie:
      # favor longer paths through target locations over shorter paths with additional locations.
      def route_type_to_locations_via_search(type_name, start_location, goal_locations)
        results = {}
        costs = {}

        paths = possible_keys_for_type_and_location(type_name, start_location).map do |possible_key|
          [{ location: start_location, key: possible_key, cost: 0 }]
        end

        while paths.any?
          path = paths.pop
          current_location = path.last[:location]
          current_key = path.last[:key]
          current_cost = path.last[:cost]

          @boundaries[type_name].each do |boundary|
            forward_location = boundary["location"]
            next if current_key != boundary["key"]
            next if path.any? { _1[:location] == forward_location }

            best_cost = costs[forward_location] || Float::INFINITY
            next if best_cost < current_cost

            path.pop
            path << {
              location: current_location,
              key: current_key,
              cost: current_cost,
              boundary: boundary,
            }

            if goal_locations.include?(forward_location)
              current_result = results[forward_location]
              if current_result.nil? || current_cost < best_cost || (current_cost == best_cost && path.length < current_result.length)
                results[forward_location] = path.map { _1[:boundary] }
              end
            else
              path.last[:cost] += 1
            end

            forward_cost = path.last[:cost]
            costs[forward_location] = forward_cost if forward_cost < best_cost

            possible_keys_for_type_and_location(type_name, forward_location).each do |possible_key|
              paths << [*path, { location: forward_location, key: possible_key, cost: forward_cost }]
            end
          end

          paths.sort! do |a, b|
            cost_diff = a.last[:cost] - b.last[:cost]
            cost_diff.zero? ? a.length - b.length : cost_diff
          end.reverse!
        end

        results
      end
    end
  end
end
