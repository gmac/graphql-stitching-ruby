# frozen_string_literal: true

module GraphQL::Stitching
  class Composer
    class ValidateBoundaries < BaseValidator

      def perform(supergraph, composer)
        supergraph.schema.types.each do |type_name, type|
          # objects and interfaces that are not the root operation types
          next unless type.kind.object? || type.kind.interface?
          next if supergraph.schema.query == type || supergraph.schema.mutation == type
          next if type.graphql_name.start_with?("__")

          # multiple subschemas implement the type
          candidate_types_by_location = composer.candidate_types_by_name_and_location[type_name]
          next unless candidate_types_by_location.length > 1

          boundaries = supergraph.boundaries[type_name]
          if boundaries&.any?
            validate_as_boundary(supergraph, type, candidate_types_by_location, boundaries)
          elsif type.kind.object?
            validate_as_shared(supergraph, type, candidate_types_by_location)
          end
        end
      end

      private

      def validate_as_boundary(supergraph, type, candidate_types_by_location, boundaries)
        # abstract boundaries are expanded with their concrete implementations, which each get validated. Ignore the abstract itself.
        return if type.kind.abstract?

        # only one boundary allowed per type/location/key
        boundaries_by_location_and_key = boundaries.each_with_object({}) do |boundary, memo|
          if memo.dig(boundary.location, boundary.key)
            raise Composer::ValidationError, "Multiple boundary queries for `#{type.graphql_name}.#{boundary.key}` "\
              "found in #{boundary.location}. Limit one boundary query per type and key in each location. "\
              "Abstract boundaries provide all possible types."
          end
          memo[boundary.location] ||= {}
          memo[boundary.location][boundary.key] = boundary
        end

        boundary_keys = boundaries.map(&:key).to_set

        # All non-key fields must be resolvable in at least one boundary location
        supergraph.locations_by_type_and_field[type.graphql_name].each do |field_name, locations|
          next if boundary_keys.include?(field_name)

          if locations.none? { boundaries_by_location_and_key[_1] }
            where = locations.length > 1 ? "one of #{locations.join(", ")} locations" : locations.first
            raise Composer::ValidationError, "A boundary query is required for `#{type.graphql_name}` in #{where} to resolve field `#{field_name}`."
          end
        end

        # All locations of a boundary type must include at least one key field
        supergraph.fields_by_type_and_location[type.graphql_name].each do |location, field_names|
          if field_names.none? { boundary_keys.include?(_1) }
            raise Composer::ValidationError, "A boundary key is required for `#{type.graphql_name}` in #{location} to join with other locations."
          end
        end

        # verify that all outbound locations can access all inbound locations
        resolver_locations = boundaries_by_location_and_key.keys
        candidate_types_by_location.each_key do |location|
          remote_locations = resolver_locations.reject { _1 == location }
          paths = supergraph.route_type_to_locations(type.graphql_name, location, remote_locations)
          if paths.length != remote_locations.length || paths.any? { |_loc, path| path.nil? }
            raise Composer::ValidationError, "Cannot route `#{type.graphql_name}` boundaries in #{location} to all other locations. "\
              "All locations must provide a boundary accessor that uses a conjoining key."
          end
        end
      end

      def validate_as_shared(supergraph, type, candidate_types_by_location)
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

        candidate_types_by_location.each do |location, candidate_type|
          if candidate_type.fields.keys.sort != expected_fields
            raise Composer::ValidationError, "Shared type `#{type.graphql_name}` must have consistent fields across locations, "\
              "or else define boundary queries so that its unique fields may be accessed remotely."
          end
        end
      end
    end
  end
end
