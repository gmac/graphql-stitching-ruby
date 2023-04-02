# frozen_string_literal: true

module GraphQL
  module Stitching
    class Composer::ValidateBoundaries < Composer::BaseValidator

      def perform(ctx, composer)
        ctx.schema.types.each do |type_name, type|
          # objects and interfaces that are not the root operation types
          next unless type.kind.object? || type.kind.interface?
          next if ctx.schema.query == type || ctx.schema.mutation == type
          next if type.graphql_name.start_with?("__")

          # multiple subschemas implement the type
          candidate_types_by_location = composer.candidate_types_by_name_and_location[type_name]
          next unless candidate_types_by_location.length > 1

          boundaries = ctx.boundaries[type_name]
          if boundaries&.any?
            validate_as_boundary(ctx, type, candidate_types_by_location, boundaries)
          elsif type.kind.object?
            validate_as_shared(ctx, type, candidate_types_by_location)
          end
        end
      end

      private

      def validate_as_boundary(ctx, type, candidate_types_by_location, boundaries)
        # abstract boundaries are expanded with their concrete implementations, which each get validated. Ignore the abstract itself.
        return if type.kind.abstract?

        # only one boundary allowed per type/location/key
        boundaries_by_location_and_key = boundaries.each_with_object({}) do |boundary, memo|
          if memo.dig(boundary["location"], boundary["key"])
            raise Composer::ValidationError, "Multiple boundary queries for `#{type.graphql_name}.#{boundary["key"]}` "\
              "found in #{boundary["location"]}. Limit one boundary query per type and key in each location. "\
              "Abstract boundaries provide all possible types."
          end
          memo[boundary["location"]] ||= {}
          memo[boundary["location"]][boundary["key"]] = boundary
        end

        boundary_keys = boundaries.map { _1["key"] }.uniq
        key_only_types_by_location = candidate_types_by_location.select do |location, subschema_type|
          subschema_type.fields.keys.length == 1 && boundary_keys.include?(subschema_type.fields.keys.first)
        end

        # all locations have a boundary, or else are key-only
        candidate_types_by_location.each do |location, subschema_type|
          unless boundaries_by_location_and_key[location] || key_only_types_by_location[location]
            raise Composer::ValidationError, "A boundary query is required for `#{type.graphql_name}` in #{location} because it provides unique fields."
          end
        end

        outbound_access_locations = key_only_types_by_location.keys
        bidirectional_access_locations = candidate_types_by_location.keys - outbound_access_locations

        # verify that all outbound locations can access all inbound locations
        (outbound_access_locations + bidirectional_access_locations).each do |location|
          remote_locations = bidirectional_access_locations.reject { _1 == location }
          paths = ctx.route_type_to_locations(type.graphql_name, location, remote_locations)
          if paths.length != remote_locations.length || paths.any? { |_loc, path| path.nil? }
            raise Composer::ValidationError, "Cannot route `#{type.graphql_name}` boundaries in #{location} to all other locations. "\
              "All locations must provide a boundary accessor that uses a conjoining key."
          end
        end
      end

      def validate_as_shared(ctx, type, candidate_types_by_location)
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

        candidate_types_by_location.each do |location, subschema_type|
          if subschema_type.fields.keys.sort != expected_fields
            raise Composer::ValidationError, "Shared type `#{type.graphql_name}` must have consistent fields across locations, "\
              "or else define boundary queries so that its unique fields may be accessed remotely."
          end
        end
      end
    end
  end
end
