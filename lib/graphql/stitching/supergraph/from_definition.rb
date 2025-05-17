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
        if schema.is_a?(String)
          schema = if GraphQL::Stitching.supports_visibility?
            GraphQL::Schema.from_definition(schema, base_types: BASE_TYPES)
          else
            GraphQL::Schema.from_definition(schema)
          end
        end

        field_map = {}
        resolver_map = {}
        possible_locations = {}
        visibility_definition = schema.directives[GraphQL::Stitching.visibility_directive]
        visibility_profiles = visibility_definition&.get_argument("profiles")&.default_value || EMPTY_ARRAY

        schema.types.each do |type_name, type|
          next if type.introspection?

          # Collect/build key definitions for each type
          locations_by_key = type.directives.each_with_object({}) do |directive, memo|
            next unless directive.graphql_name == Directives::SupergraphKey.graphql_name

            kwargs = directive.arguments.keyword_arguments
            memo[kwargs[:key]] ||= []
            memo[kwargs[:key]] << kwargs[:location]
          end

          key_definitions = locations_by_key.each_with_object({}) do |(key, locations), memo|
            memo[key] = TypeResolver.parse_key(key, locations)
          end

          # Collect/build resolver definitions for each type
          type.directives.each do |d|
            next unless d.graphql_name == Directives::SupergraphResolver.graphql_name

            kwargs = d.arguments.keyword_arguments
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
              next unless d.graphql_name == Directives::SupergraphSource.graphql_name
              
              location = d.arguments.keyword_arguments[:location]
              field_map[type_name] ||= {}
              field_map[type_name][field_name] ||= []
              field_map[type_name][field_name] << location
              possible_locations[location] = true
            end
          end
        end

        executables = possible_locations.each_key.each_with_object({}) do |location, memo|
          executable = executables[location] || executables[location.to_sym]
          if validate_executable!(location, executable)
            memo[location] = executable
          end
        end

        new(
          schema: schema,
          fields: field_map,
          resolvers: resolver_map,
          visibility_profiles: visibility_profiles,
          executables: executables,
        )
      end
    end
  end
end
