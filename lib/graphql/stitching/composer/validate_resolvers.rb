# frozen_string_literal: true

module GraphQL::Stitching
  class Composer
    class ValidateResolvers < BaseValidator

      def perform(supergraph, composer)
        supergraph.schema.types.each do |type_name, type|
          # objects and interfaces that are not the root operation types
          next unless type.kind.object? || type.kind.interface?
          next if supergraph.schema.query == type || supergraph.schema.mutation == type
          next if type.graphql_name.start_with?("__")

          # multiple subschemas implement the type
          subgraph_types_by_location = composer.subgraph_types_by_name_and_location[type_name]
          next unless subgraph_types_by_location.length > 1

          resolvers = supergraph.resolvers[type_name]
          if resolvers&.any?
            validate_as_resolver(supergraph, type, subgraph_types_by_location, resolvers)
          elsif type.kind.object?
            validate_as_shared(supergraph, type, subgraph_types_by_location)
          end
        end
      end

      private

      def validate_as_resolver(supergraph, type, subgraph_types_by_location, resolvers)
        # abstract resolvers are expanded with their concrete implementations, which each get validated. Ignore the abstract itself.
        return if type.kind.abstract?

        # only one resolver allowed per type/location/key
        resolvers_by_location_and_key = resolvers.each_with_object({}) do |resolver, memo|
          if memo.dig(resolver.location, resolver.key)
            raise Composer::ValidationError, "Multiple resolver queries for `#{type.graphql_name}.#{resolver.key}` "\
              "found in #{resolver.location}. Limit one resolver query per type and key in each location. "\
              "Abstract resolvers provide all possible types."
          end
          memo[resolver.location] ||= {}
          memo[resolver.location][resolver.key] = resolver
        end

        resolver_keys = resolvers.map(&:key).to_set

        # All non-key fields must be resolvable in at least one resolver location
        supergraph.locations_by_type_and_field[type.graphql_name].each do |field_name, locations|
          next if resolver_keys.include?(field_name)

          if locations.none? { resolvers_by_location_and_key[_1] }
            where = locations.length > 1 ? "one of #{locations.join(", ")} locations" : locations.first
            raise Composer::ValidationError, "A resolver query is required for `#{type.graphql_name}` in #{where} to resolve field `#{field_name}`."
          end
        end

        # All locations of a resolver type must include at least one key field
        supergraph.fields_by_type_and_location[type.graphql_name].each do |location, field_names|
          if field_names.none? { resolver_keys.include?(_1) }
            raise Composer::ValidationError, "A resolver key is required for `#{type.graphql_name}` in #{location} to join with other locations."
          end
        end

        # verify that all outbound locations can access all inbound locations
        resolver_locations = resolvers_by_location_and_key.keys
        subgraph_types_by_location.each_key do |location|
          remote_locations = resolver_locations.reject { _1 == location }
          paths = supergraph.route_type_to_locations(type.graphql_name, location, remote_locations)
          if paths.length != remote_locations.length || paths.any? { |_loc, path| path.nil? }
            raise Composer::ValidationError, "Cannot route `#{type.graphql_name}` resolvers in #{location} to all other locations. "\
              "All locations must provide a resolver query with a joining key."
          end
        end
      end

      def validate_as_shared(supergraph, type, subgraph_types_by_location)
        expected_fields = begin
          type.fields.keys.sort
        rescue StandardError => e
          # bug with inherited interfaces in older versions of GraphQL
          if type.interfaces.any? { _1.is_a?(GraphQL::Schema::LateBoundType) }
            raise Composer::ComposerError, "Merged interface inheritance requires GraphQL >= v2.0.3"
          else
            raise e
          end
        end

        subgraph_types_by_location.each do |location, subgraph_type|
          if subgraph_type.fields.keys.sort != expected_fields
            raise Composer::ValidationError, "Shared type `#{type.graphql_name}` must have consistent fields across locations, "\
              "or else define resolver queries so that its unique fields may be accessed remotely."
          end
        end
      end
    end
  end
end
