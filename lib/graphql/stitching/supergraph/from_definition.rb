# frozen_string_literal: true

module GraphQL::Stitching
  class Supergraph
    class << self
      def validate_executable!(location, executable)
        return true if executable.is_a?(Class) && executable <= GraphQL::Schema
        return true if executable && executable.respond_to?(:call)
        raise StitchingError, "Invalid executable provided for location `#{location}`."
      end

      def from_definition(schema, executables:)
        schema = GraphQL::Schema.from_definition(schema) if schema.is_a?(String)
        field_map = {}
        resolver_map = {}
        possible_locations = {}

        schema.types.each do |type_name, type|
          next if type.introspection?

          # Collect/build key definitions for each type
          locations_by_key = type.directives.each_with_object({}) do |directive, memo|
            next unless directive.graphql_name == Composer::KeyDirective.graphql_name

            kwargs = directive.arguments.keyword_arguments
            memo[kwargs[:key]] ||= []
            memo[kwargs[:key]] << kwargs[:location]
          end

          key_definitions = locations_by_key.each_with_object({}) do |(key, locations), memo|
            memo[key] = TypeResolver.parse_key(key, locations)
          end

          # Collect/build resolver definitions for each type
          type.directives.each do |directive|
            next unless directive.graphql_name == Composer::ResolverDirective.graphql_name

            kwargs = directive.arguments.keyword_arguments
            resolver_map[type_name] ||= []
            resolver_map[type_name] << TypeResolver.new(
              location: kwargs[:location],
              type_name: kwargs.fetch(:type_name, type_name),
              field: kwargs[:field],
              list: kwargs[:list] || false,
              key: key_definitions[kwargs[:key]],
              arguments: TypeResolver.parse_arguments_with_type_defs(kwargs[:arguments], kwargs[:argument_types]),
            )
          end

          next unless type.kind.fields?

          type.fields.each do |field_name, field|
            # Collection locations for each field definition
            field.directives.each do |d|
              next unless d.graphql_name == Composer::SourceDirective.graphql_name

              location = d.arguments.keyword_arguments[:location]
              field_map[type_name] ||= {}
              field_map[type_name][field_name] ||= []
              field_map[type_name][field_name] << location
              possible_locations[location] = true
            end
          end
        end

        executables = possible_locations.keys.each_with_object({}) do |location, memo|
          executable = executables[location] || executables[location.to_sym]
          if validate_executable!(location, executable)
            memo[location] = executable
          end
        end

        new(
          schema: schema,
          fields: field_map,
          resolvers: resolver_map,
          executables: executables,
        )
      end
    end
  end
end
