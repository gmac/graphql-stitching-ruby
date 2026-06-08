# frozen_string_literal: true
# typed: true

require_relative "supergraph/types"
require_relative "supergraph/index"
require_relative "supergraph/from_definition"

module GraphQL
  module Stitching
    # Supergraph is the singuar representation of a stitched graph.
    # It provides the combined GraphQL schema and delegation maps
    # used to route selections across subgraph locations.
    class Supergraph
      SUPERGRAPH_LOCATION = "__super"

      #: singleton(GraphQL::Schema)
      attr_reader :schema

      #: Hash[Location, Executable]
      attr_reader :executables

      #: TypeResolverMap
      attr_reader :resolvers

      #: Hash[TypeName, CompositeType]
      attr_reader :memoized_schema_types

      #: Hash[TypeName, GraphQL::Schema::Member]
      attr_reader :memoized_introspection_types

      #: LocationsByTypeAndField
      attr_reader :locations_by_type_and_field

      # @rbs!
      #   @resolvers_by_version: Hash[String, TypeResolver]?
      #   @fields_by_type_and_location: FieldsByTypeAndLocation?
      #   @locations_by_type: LocationsByType?
      #   @memoized_schema_fields: Hash[TypeName, Hash[FieldName, GraphQL::Schema::Field]]
      #   @possible_keys_by_type: Hash[TypeName, Array[TypeResolver::Key]]
      #   @possible_keys_by_type_and_location: Hash[TypeName, Hash[Location, Array[TypeResolver::Key]]]

      #: (
      #|   schema: singleton(GraphQL::Schema),
      #|   ?fields: LocationsByTypeAndField,
      #|   ?resolvers: TypeResolverMap,
      #|   ?visibility_profiles: Array[String],
      #|   ?executables: Hash[Location | Symbol, Executable]
      #| ) -> void
      def initialize(schema:, fields: {}, resolvers: {}, visibility_profiles: [], executables: {})
        @schema = schema
        @resolvers = resolvers
        @resolvers_by_version = nil
        @memoized_introspection_types = @schema.introspection_system.types
        @memoized_schema_types = @schema.types
        @memoized_schema_fields = {}
        @possible_keys_by_type = {}
        @possible_keys_by_type_and_location = {}
        index = Index.new(
          schema: @schema,
          fields: fields,
          supergraph_location: SUPERGRAPH_LOCATION,
        )
        @locations_by_type_and_field = index.locations_by_type_and_field
        @fields_by_type_and_location = index.fields_by_type_and_location
        @locations_by_type = index.locations_by_type

        # validate and normalize executable references
        @executables = executables.each_with_object({ SUPERGRAPH_LOCATION => @schema }) do |(location, executable), memo|
          if self.class.validate_executable!(location, executable)
            memo[location.to_s] = executable
          end
        end.freeze

        if visibility_profiles.empty?
          @schema.use(GraphQL::Schema::AlwaysVisible)
        else
          profiles = visibility_profiles.each_with_object({ nil => {} }) { |p, m| m[p.to_s] = {} }
          @schema.use(GraphQL::Schema::Visibility, profiles: profiles)
        end
      end

      #: (?visibility_profile: String?) -> String
      def to_definition(visibility_profile: nil)
        @schema.to_definition(context: {
          visibility_profile: visibility_profile,
        }.tap(&:compact!))
      end

      #: -> Hash[String, TypeResolver]
      def resolvers_by_version
        @resolvers_by_version ||= resolvers.values.flatten.each_with_object({}) do |resolver, memo|
          memo[resolver.version] = resolver
        end
      end

      #: -> LocationsByTypeAndField
      def fields
        @locations_by_type_and_field.each_with_object({}) do |(type_name, fields), memo|
          next if memoized_introspection_types[type_name]

          memo[type_name] = fields.reject do |field_name, locations|
            locations == [SUPERGRAPH_LOCATION] && @schema.introspection_system.entry_point(name: field_name)
          end
        end
      end

      #: -> Array[Location]
      def locations
        @executables.each_key.reject { _1 == SUPERGRAPH_LOCATION }
      end

      #: (TypeName type_name) -> Hash[FieldName, GraphQL::Schema::Field]
      def memoized_schema_fields(type_name)
        @memoized_schema_fields[type_name] ||= begin
          type = @memoized_schema_types[type_name]
          fields = type.kind.fields? ? type.fields.dup : {}
          @schema.introspection_system.dynamic_fields.each do |field|
            fields[field.name] ||= field # adds __typename
          end

          if type_name == @schema.query.graphql_name
            @schema.introspection_system.entry_points.each do |field|
              fields[field.name] ||= field # adds __schema, __type
            end
          end

          fields.freeze
        end
      end

      #: (Location location, String source, Variables variables, Request request) -> untyped
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
      #: -> FieldsByTypeAndLocation
      def fields_by_type_and_location
        @fields_by_type_and_location
      end

      #: -> LocationsByType
      def locations_by_type
        @locations_by_type
      end

      # collects all possible resolver keys for a given type
      #: (TypeName type_name) -> Array[TypeResolver::Key]
      def possible_keys_for_type(type_name)
        @possible_keys_by_type[type_name] ||= begin
          if type_name == @schema.query.graphql_name
            GraphQL::Stitching::EMPTY_ARRAY
          else
            (@resolvers[type_name] || GraphQL::Stitching::EMPTY_ARRAY).map(&:key).uniq(&:to_definition)
          end
        end
      end

      # collects possible resolver keys for a given type and location
      #: (TypeName type_name, Location location) -> Array[TypeResolver::Key]
      def possible_keys_for_type_and_location(type_name, location)
        possible_keys_by_type = @possible_keys_by_type_and_location[type_name] ||= {}
        possible_keys_by_type[location] ||= possible_keys_for_type(type_name).select do |key|
          next true if key.locations.include?(location)

          # Outbound-only locations without resolver queries may dynamically match primitive keys
          location_fields = fields_by_type_and_location[type_name]&.[](location) || GraphQL::Stitching::EMPTY_ARRAY
          location_fields.include?(key.primitive_name)
        end
      end

      # For a given type, route from one origin location to one or more remote locations
      # used to connect a partial type across locations via resolver queries
      #: (TypeName type_name, Location start_location, Enumerable[Location] goal_locations) -> TypeResolverRoutes
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
          (@resolvers[type_name] || GraphQL::Stitching::EMPTY_ARRAY).each_with_object({}) do |resolver, memo|
            if goal_locations.include?(resolver.location)
              memo[resolver.location] = [resolver]
            end
          end
        end
      end

      private

      class PathNode
        #: Location
        attr_reader :location

        #: TypeResolver::Key
        attr_reader :key

        #: TypeResolver?
        attr_reader :resolver

        #: Integer
        attr_accessor :cost

        #: (location: Location, key: TypeResolver::Key, ?resolver: TypeResolver?, ?cost: Integer) -> void
        def initialize(location:, key:, resolver: nil, cost: 0)
          @location = location
          @key = key
          @resolver = resolver
          @cost = cost
        end
      end

      # tunes A* search to favor paths with fewest joining locations, ie:
      # favor longer paths through target locations over shorter paths with additional locations.
      #: (TypeName type_name, Location start_location, Enumerable[Location] goal_locations) -> TypeResolverRoutes
      def route_type_to_locations_via_search(type_name, start_location, goal_locations)
        results = {}
        costs = {}

        paths = [] #: Array[Array[PathNode]]
        possible_keys_for_type_and_location(type_name, start_location).each do |possible_key|
          paths << [PathNode.new(location: start_location, key: possible_key)]
        end

        while !paths.empty?
          path = paths.pop
          next unless path

          last_node = path.fetch(-1)
          current_location = last_node.location
          current_key = last_node.key
          current_cost = last_node.cost

          (@resolvers[type_name] || GraphQL::Stitching::EMPTY_ARRAY).each do |resolver|
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
              path.fetch(-1).cost += 1
            end

            forward_cost = path.fetch(-1).cost
            costs[forward_location] = forward_cost if forward_cost < best_cost

            possible_keys_for_type_and_location(type_name, forward_location).each do |possible_key|
              paths << [*path, PathNode.new(location: forward_location, key: possible_key, cost: forward_cost)]
            end
          end

          paths.sort! do |a, b|
            cost_diff = b.fetch(-1).cost - a.fetch(-1).cost
            cost_diff.zero? ? b.length - a.length : cost_diff
          end
        end

        results
      end
    end
  end
end
