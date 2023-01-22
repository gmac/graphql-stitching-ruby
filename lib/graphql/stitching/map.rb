# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Map
      attr_reader :schema, :locations, :boundaries, :locations_by_field

      def initialize(schema:, locations:, boundaries:, fields:)
        @schema = schema
        @locations = locations
        @boundaries = boundaries
        @locations_by_field = fields
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
