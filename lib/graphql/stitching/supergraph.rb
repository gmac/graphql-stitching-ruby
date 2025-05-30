# frozen_string_literal: true

require_relative "supergraph/types"
require_relative "supergraph/from_definition"

module GraphQL
  module Stitching
    # Supergraph is the singuar representation of a stitched graph. 
    # It provides the combined GraphQL schema and delegation maps 
    # used to route selections across subgraph locations.
    class Supergraph
      SUPERGRAPH_LOCATION = "__super"

      # @return [GraphQL::Schema] the composed schema for the supergraph.
      attr_reader :schema

      # @return [Hash<String, Executable>] a map of executable resources by location.
      attr_reader :executables

      attr_reader :resolvers
      attr_reader :memoized_schema_types
      attr_reader :memoized_introspection_types
      attr_reader :locations_by_type_and_field

      def initialize(schema:, fields: {}, resolvers: {}, visibility_profiles: [], executables: {})
        @schema = schema
        @resolvers = resolvers
        @resolvers_by_version = nil
        @fields_by_type_and_location = nil
        @locations_by_type = nil
        @memoized_introspection_types = @schema.introspection_system.types
        @memoized_schema_types = @schema.types
        @memoized_schema_fields = {}
        @possible_keys_by_type = {}
        @possible_keys_by_type_and_location = {}

        # add introspection types into the fields mapping
        @locations_by_type_and_field = @memoized_introspection_types.each_with_object(fields) do |(type_name, type), memo|
          next unless type.kind.fields?

          memo[type_name] = type.fields.each_key.each_with_object({}) do |field_name, m|
            m[field_name] = [SUPERGRAPH_LOCATION]
          end
        end.freeze

        # validate and normalize executable references
        @executables = executables.each_with_object({ SUPERGRAPH_LOCATION => @schema }) do |(location, executable), memo|
          if self.class.validate_executable!(location, executable)
            memo[location.to_s] = executable
          end
        end.freeze

        if visibility_profiles.any?
          profiles = visibility_profiles.each_with_object({ nil => {} }) { |p, m| m[p.to_s] = {} }
          @schema.use(GraphQL::Schema::Visibility, profiles: profiles)
        else
          @schema.use(GraphQL::Schema::AlwaysVisible)
        end
      end

      def to_definition(visibility_profile: nil)
        @schema.to_definition(context: { 
          visibility_profile: visibility_profile,
        }.tap(&:compact!))
      end

      def resolvers_by_version
        @resolvers_by_version ||= resolvers.values.tap(&:flatten!).each_with_object({}) do |resolver, memo|
          memo[resolver.version] = resolver
        end
      end

      def fields
        @locations_by_type_and_field.reject { |k, _v| memoized_introspection_types[k] }
      end

      def locations
        @executables.each_key.reject { _1 == SUPERGRAPH_LOCATION }
      end

      def memoized_schema_fields(type_name)
        @memoized_schema_fields[type_name] ||= begin
          fields = @memoized_schema_types[type_name].fields
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

      def execute_at_location(location, source, variables, request)
        executable = executables[location]

        if executable.nil?
          raise StitchingError, "No executable assigned for #{location} location."
        elsif executable.is_a?(Class) && executable <= GraphQL::Schema
          executable.execute(
            query: source,
            variables: variables,
            context: request.context.to_h,
            validate: false,
          )
        elsif executable.respond_to?(:call)
          executable.call(request, source, variables)
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
          memo[type_name] = fields.values.tap(&:flatten!).tap(&:uniq!)
        end
      end

      # collects all possible resolver keys for a given type
      # ("Type") => [Key("id"), ...]
      def possible_keys_for_type(type_name)
        @possible_keys_by_type[type_name] ||= begin
          if type_name == @schema.query.graphql_name
            GraphQL::Stitching::EMPTY_ARRAY
          else
            resolvers = @resolvers[type_name]
            resolvers ? resolvers.map(&:key).uniq(&:to_definition) : GraphQL::Stitching::EMPTY_ARRAY
          end
        end
      end

      # collects possible resolver keys for a given type and location
      # ("Type", "location") => [Key("id"), ...]
      def possible_keys_for_type_and_location(type_name, location)
        possible_keys_by_type = @possible_keys_by_type_and_location[type_name] ||= {}
        possible_keys_by_type[location] ||= possible_keys_for_type(type_name).select do |key|
          next true if key.locations.include?(location)

          # Outbound-only locations without resolver queries may dynamically match primitive keys
          location_fields = fields_by_type_and_location[type_name][location] || GraphQL::Stitching::EMPTY_ARRAY
          location_fields.include?(key.primitive_name)
        end
      end

      # For a given type, route from one origin location to one or more remote locations
      # used to connect a partial type across locations via resolver queries
      def route_type_to_locations(type_name, start_location, goal_locations)
        key_count = possible_keys_for_type(type_name).length

        if key_count.zero?
          # nested root scopes have no resolver keys and just return a location
          goal_locations.each_with_object({}) do |goal_location, memo|
            memo[goal_location] = [TypeResolver.new(location: goal_location)]
          end

        elsif key_count > 1
          # multiple keys use an A* search to traverse intermediary locations
          route_type_to_locations_via_search(type_name, start_location, goal_locations)

        else
          # types with a single key attribute must all be within a single hop of each other,
          # so can use a simple match to collect resolvers for the goal locations.
          @resolvers[type_name].each_with_object({}) do |resolver, memo|
            if goal_locations.include?(resolver.location)
              memo[resolver.location] = [resolver]
            end
          end
        end
      end

      private

      PathNode = Struct.new(:location, :key, :cost, :resolver, keyword_init: true)

      # tunes A* search to favor paths with fewest joining locations, ie:
      # favor longer paths through target locations over shorter paths with additional locations.
      def route_type_to_locations_via_search(type_name, start_location, goal_locations)
        results = {}
        costs = {}

        paths = possible_keys_for_type_and_location(type_name, start_location).map do |possible_key|
          [PathNode.new(location: start_location, key: possible_key, cost: 0)]
        end

        while paths.any?
          path = paths.pop
          current_location = path.last.location
          current_key = path.last.key
          current_cost = path.last.cost

          @resolvers[type_name].each do |resolver|
            forward_location = resolver.location
            next if current_key != resolver.key
            next if path.any? { _1.location == forward_location }

            best_cost = costs[forward_location] || Float::INFINITY
            next if best_cost < current_cost

            path.pop
            path << PathNode.new(
              location: current_location,
              key: current_key,
              cost: current_cost,
              resolver: resolver,
            )

            if goal_locations.include?(forward_location)
              current_result = results[forward_location]
              if current_result.nil? || current_cost < best_cost || (current_cost == best_cost && path.length < current_result.length)
                results[forward_location] = path.map(&:resolver)
              end
            else
              path.last.cost += 1
            end

            forward_cost = path.last.cost
            costs[forward_location] = forward_cost if forward_cost < best_cost

            possible_keys_for_type_and_location(type_name, forward_location).each do |possible_key|
              paths << [*path, PathNode.new(location: forward_location, key: possible_key, cost: forward_cost)]
            end
          end

          paths.sort! do |a, b|
            cost_diff = b.last.cost - a.last.cost
            cost_diff.zero? ? b.length - a.length : cost_diff
          end
        end

        results
      end
    end
  end
end
