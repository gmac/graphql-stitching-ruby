# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Composer::ValidateBoundaries
      def perform(ctx, composer)
        ctx.schema.types.each do |type_name, type|
          # objects and interfaces that are not the root operation types
          next unless type.kind.name == "OBJECT" || type.kind.name == "INTERFACE"
          next if ctx.schema.query == type || ctx.schema.mutation == type
          next if type.graphql_name.start_with?("__")

          # multiple subschemas implement the type
          subschema_types_by_location = composer.subschema_types_by_name_and_location[type_name]
          next unless subschema_types_by_location.length > 1

          boundaries = ctx.boundaries[type_name]
          if boundaries&.any?
            validate_as_boundary(ctx, type, subschema_types_by_location, boundaries)
          elsif type.kind.name == "OBJECT"
            validate_as_shared(ctx, type, subschema_types_by_location)
          end
        end
      end

      private

      def validate_as_boundary(ctx, type, subschema_types_by_location, boundaries)
        # only one boundary allowed per type/location/key
        boundaries_by_location_and_key = boundaries.each_with_object({}) do |boundary, memo|
          if memo.dig(boundary["location"], boundary["selection"])
            raise ValidationError, "Multiple boundary queries for `#{type.graphql_name}.#{boundary["selection"]}` found in #{boundary["location"]}.
            Limit one boundary query per type and key in each location. Abstract boundaries provide all possible types."
          end
          memo[boundary["location"]] ||= {}
          memo[boundary["location"]][boundary["selection"]] = boundary
        end

        boundary_keys = boundaries.map { _1["selection"] }.uniq
        key_only_types_by_location = subschema_types_by_location.select do |location, subschema_type|
          subschema_type.fields.keys.length == 1 && boundary_keys.include?(subschema_type.fields.keys.first)
        end

        # all locations have a boundary, or else are key-only
        subschema_types_by_location.each do |location, subschema_type|
          unless boundaries_by_location_and_key[location] || key_only_types_by_location[location]
            raise ValidationError, "A boundary query is required for `#{type.graphql_name}` in #{location} to share its unique fields across locations."
          end
        end

        outbound_access_locations = key_only_types_by_location.keys
        bidirectional_access_locations = subschema_types_by_location.keys - outbound_access_locations

        # verify that all outbound locations can access all inbound locations
        (outbound_access_locations + bidirectional_access_locations).each do |location|
          remote_locations = bidirectional_access_locations.reject { _1 == location }
          paths = ctx.route_to_locations(type.graphql_name, location, remote_locations)
          if paths.length != remote_locations.length || paths.any? { |_loc, path| path.nil? }
            raise ValidationError, "Cannot route `#{type.graphql_name}` boundaries in #{location} to all other locations.
            All locations must provide a boundary accessor that uses a conjoining key."
          end
        end
      end

      def validate_as_shared(ctx, type, subschema_types_by_location)
        expected_fields = type.fields.keys.sort
        subschema_types_by_location.each do |location, subschema_type|
          if subschema_type.fields.keys.sort != expected_fields
            raise ValidationError, "Shared type `#{type.graphql_name}` must have consistent fields across locations,
            or else define boundary queries so that its unique fields may be accessed remotely."
          end
        end
      end
    end
  end
end
