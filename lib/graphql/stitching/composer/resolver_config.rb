# frozen_string_literal: true

module GraphQL::Stitching
  class Composer
    class ResolverConfig
      ENTITY_TYPENAME = "_Entity"
      ENTITIES_QUERY = "_entities"

      class << self
        def extract_directive_assignments(schema, location, assignments)
          return EMPTY_OBJECT unless assignments && assignments.any?

          assignments.each_with_object({}) do |kwargs, memo|
            type = kwargs[:parent_type_name] ? schema.get_type(kwargs[:parent_type_name]) : schema.query
            raise ComposerError, "Invalid stitch directive type `#{kwargs[:parent_type_name]}`" unless type

            field = type.get_field(kwargs[:field_name])
            raise ComposerError, "Invalid stitch directive field `#{kwargs[:field_name]}`" unless field

            field_path = "#{location}.#{field.name}"
            memo[field_path] ||= []
            memo[field_path] << from_kwargs(kwargs)
          end
        end

        def extract_federation_entities(schema, location)
          return EMPTY_OBJECT unless federation_entities_schema?(schema)

          schema.possible_types(schema.get_type(ENTITY_TYPENAME)).each_with_object({}) do |entity_type, memo|
            entity_type.directives.each do |directive|
              next unless directive.graphql_name == "key"

              key = directive.arguments.keyword_arguments.fetch(:fields).strip
              raise ComposerError, "Composite federation keys are not supported." unless /^\w+$/.match?(key)

              field_path = "#{location}._entities"
              memo[field_path] ||= []
              memo[field_path] << new(
                key: key,
                type_name: entity_type.graphql_name,
                representations: true,
              )
            end
          end
        end

        def from_kwargs(kwargs)
          new(
            key: kwargs[:key],
            type_name: kwargs[:type_name] || kwargs[:typeName],
            representations: kwargs[:representations] || false,
          )
        end

        private

        def federation_entities_schema?(schema)
          entity_type = schema.get_type(ENTITY_TYPENAME)
          entities_query = schema.query.get_field(ENTITIES_QUERY)
          entity_type && entity_type.kind.union? && entities_query && entities_query.type.unwrap == entity_type
        end
      end

      attr_reader :key, :type_name, :representations

      def initialize(key:, type_name:, representations: false)
        @key = key
        @type_name = type_name
        @representations = representations
      end
    end
  end
end
