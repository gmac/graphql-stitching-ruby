# frozen_string_literal: true
require_relative "./key_directive"
require_relative "./resolver_directive"
require_relative "./source_directive"

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
            next unless directive.graphql_name == KeyDirective.graphql_name

            kwargs = directive.arguments.keyword_arguments
            memo[kwargs[:key]] ||= []
            memo[kwargs[:key]] << kwargs[:location]
          end

          key_definitions = locations_by_key.each_with_object({}) do |(key, locations), memo|
            memo[key] = TypeResolver.parse_key(key, locations)
          end

          # Collect/build resolver definitions for each type
          type.directives.each do |directive|
            next unless directive.graphql_name == ResolverDirective.graphql_name

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
              next unless d.graphql_name == SourceDirective.graphql_name

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

    def to_definition
      if @schema.directives[KeyDirective.graphql_name].nil?
        @schema.directive(KeyDirective)
      end
      if @schema.directives[ResolverDirective.graphql_name].nil?
        @schema.directive(ResolverDirective)
      end
      if @schema.directives[SourceDirective.graphql_name].nil?
        @schema.directive(SourceDirective)
      end

      @schema.types.each do |type_name, type|
        if resolvers_for_type = @resolvers.dig(type_name)
          # Apply key directives for each unique type/key/location
          # (this allows keys to be composite selections and/or omitted from the supergraph schema)
          keys_for_type = resolvers_for_type.each_with_object({}) do |resolver, memo|
            memo[resolver.key.to_definition] ||= Set.new
            memo[resolver.key.to_definition].merge(resolver.key.locations)
          end

          keys_for_type.each do |key, locations|
            locations.each do |location|
              params = { key: key, location: location }

              unless has_directive?(type, KeyDirective.graphql_name, params)
                type.directive(KeyDirective, **params)
              end
            end
          end

          # Apply resolver directives for each unique query resolver
          resolvers_for_type.each do |resolver|
            params = {
              location: resolver.location,
              field: resolver.field,
              list: resolver.list? || nil,
              key: resolver.key.to_definition,
              arguments: resolver.arguments.map(&:to_definition).join(", "),
              argument_types: resolver.arguments.map(&:to_type_definition).join(", "),
              type_name: (resolver.type_name if resolver.type_name != type_name),
            }

            unless has_directive?(type, ResolverDirective.graphql_name, params)
              type.directive(ResolverDirective, **params.tap(&:compact!))
            end
          end
        end

        next unless type.kind.fields?

        type.fields.each do |field_name, field|
          locations_for_field = @locations_by_type_and_field.dig(type_name, field_name)
          next if locations_for_field.nil?

          # Apply source directives to annotate the possible locations of each field
          locations_for_field.each do |location|
            params = { location: location }

            unless has_directive?(field, SourceDirective.graphql_name, params)
              field.directive(SourceDirective, **params)
            end
          end
        end
      end

      @schema.to_definition
    end

    private

    def has_directive?(element, directive_name, params)
      existing = element.directives.find do |d|
        kwargs = d.arguments.keyword_arguments
        d.graphql_name == directive_name && params.all? { |k, v| kwargs[k] == v }
      end

      !existing.nil?
    end
  end
end
