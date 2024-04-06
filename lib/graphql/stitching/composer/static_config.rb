# frozen_string_literal: true

module GraphQL::Stitching
  class Composer
    class StaticConfig

      ENTITY_TYPENAME = "_Entity"
      ENTITIES_QUERY = "_entities"

      class << self
        def extract_directive_assignments(schema, location, assignments)
          return nil unless assignments && assignments.any?

          assignments.each_with_object({}) do |cfg, memo|
            type = cfg[:parent_type_name] ? schema.get_type(cfg[:parent_type_name]) : schema.query
            raise ComposerError, "Invalid stitch directive type `#{cfg[:parent_type_name]}`" unless type

            field = type.get_field(cfg[:field_name])
            raise ComposerError, "Invalid stitch directive field `#{cfg[:field_name]}`" unless field

            field_path = "#{location}.#{field.name}"
            memo[field_path] ||= []
            memo[field_path] << cfg.slice(:key, :type_name)
          end
        end

        def extract_federation_entities(schema, location)
          return nil unless has_federation_entities?(schema)

          result = {}
          schema.possible_types(schema.get_type(ENTITY_TYPENAME)).each do |entity_type|
            entity_type.directives.each do |directive|
              next unless directive.graphql_name == "key"

              key = directive.arguments.keyword_arguments.fetch(:fields).strip
              raise ComposerError, "Composite federation keys are not supported." unless /^\w+$/.match?(key)

              field_path = "#{location}._entities"
              result[field_path] ||= []
              result[field_path] << {
                key: key,
                type_name: entity_type.graphql_name,
                federation: true,
              }
            end
          end

          result
        end

        private

        def has_federation_entities?(schema)
          entity_type = schema.get_type(ENTITY_TYPENAME)
          entities_query = schema.query.get_field(ENTITIES_QUERY)
          entity_type && entity_type.kind.union? && entities_query && entities_query.type.unwrap == entity_type
        end
      end
    end
  end
end
