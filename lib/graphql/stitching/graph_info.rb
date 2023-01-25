# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class GraphInfo
      attr_reader :schema, :locations, :boundaries, :locations_by_field

      def initialize(schema:, locations:, boundaries:, fields:, arguments: {})
        @schema = schema
        @locations = locations
        @boundaries = boundaries
        @locations_by_field = fields
        @locations_by_argument = arguments
      end

      def delegation_map
        {
          locations: @locations,
          boundaries: @boundaries,
          fields: @locations_by_field,
          arguments: @locations_by_argument,
        }
      end

      def fields_by_location
        # invert fields map to provide fields for a type/location
        @fields_by_location ||= locations_by_field.each_with_object({}) do |(typename, fields), memo|
          memo[typename] = fields.each_with_object({}) do |(fieldname, locations), memo|
            locations.each do |location|
              memo[location] ||= []
              memo[location] << fieldname
            end
          end
        end
      end
    end
  end
end
