# frozen_string_literal: true

module GraphQL::Stitching
  class Supergraph
    # Immutable lookup tables for stitching-specific schema ownership.
    class Index
      attr_reader :locations_by_type_and_field
      attr_reader :fields_by_type_and_location
      attr_reader :locations_by_type

      def initialize(schema:, fields:, supergraph_location:)
        locations_by_type_and_field = normalize_locations_by_type_and_field(fields)
        add_introspection_locations(locations_by_type_and_field, schema, supergraph_location)

        @locations_by_type_and_field = freeze_nested_hash(locations_by_type_and_field)
        @fields_by_type_and_location = freeze_nested_hash(invert_fields_by_type_and_location(locations_by_type_and_field))
        @locations_by_type = freeze_type_locations(locations_by_type_and_field)
      end

      private

      def normalize_locations_by_type_and_field(fields)
        fields.each_with_object({}) do |(type_name, field_locations), type_memo|
          type_memo[type_name.to_s] = field_locations.each_with_object({}) do |(field_name, locations), field_memo|
            field_memo[field_name.to_s] = locations.map(&:to_s).uniq.freeze
          end
        end
      end

      def add_introspection_locations(locations_by_type_and_field, schema, supergraph_location)
        schema.introspection_system.types.each do |type_name, type|
          next unless type.kind.fields?

          locations_by_type_and_field[type_name] = type.fields.each_key.each_with_object({}) do |field_name, memo|
            memo[field_name] = [supergraph_location].freeze
          end
        end

        query_type_name = schema.query&.graphql_name
        return unless query_type_name && locations_by_type_and_field[query_type_name]

        schema.introspection_system.entry_points.each do |field|
          locations_by_type_and_field[query_type_name][field.name] ||= [supergraph_location].freeze
        end
      end

      def invert_fields_by_type_and_location(locations_by_type_and_field)
        locations_by_type_and_field.each_with_object({}) do |(type_name, fields), type_memo|
          type_memo[type_name] = fields.each_with_object({}) do |(field_name, locations), location_memo|
            locations.each do |location|
              location_memo[location] ||= []
              location_memo[location] << field_name
            end
          end
        end
      end

      def freeze_type_locations(locations_by_type_and_field)
        locations_by_type_and_field.each_with_object({}) do |(type_name, fields), memo|
          locations = fields.values.flatten.uniq
          memo[type_name] = locations.freeze
        end.freeze
      end

      def freeze_nested_hash(hash)
        hash.each_value do |value|
          if value.is_a?(Hash)
            freeze_nested_hash(value)
          elsif value.is_a?(Array)
            value.freeze
          end
        end
        hash.freeze
      end
    end
  end
end
