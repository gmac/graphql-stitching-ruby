# frozen_string_literal: true

require_relative "composer/base_validator"
require_relative "composer/supergraph_directives"
require_relative "composer/validate_interfaces"
require_relative "composer/validate_type_resolvers"
require_relative "composer/type_resolver_config"

module GraphQL
  module Stitching
    # Composer receives many individual `GraphQL::Schema` instances 
    # representing various graph locations and merges them into one 
    # combined Supergraph that is validated for integrity.
    class Composer
      # @api private
      NO_DEFAULT_VALUE = begin
        t = Class.new(GraphQL::Schema::Object) do
          field(:f, String) { _1.argument(:a, String) }
        end

        t.get_field("f").get_argument("a").default_value
      end

      # @api private
      BASIC_VALUE_MERGER = ->(values_by_location, _info) { values_by_location.values.find { !_1.nil? } }

      # @api private
      BASIC_ROOT_FIELD_LOCATION_SELECTOR = ->(locations, _info) { locations.last }

      # @api private
      COMPOSITION_VALIDATORS = [
        ValidateInterfaces,
        ValidateTypeResolvers,
      ].freeze

      # @return [String] name of the Query type in the composed schema.
      attr_reader :query_name

      # @return [String] name of the Mutation type in the composed schema.
      attr_reader :mutation_name

      # @return [String] name of the Subscription type in the composed schema.
      attr_reader :subscription_name

      # @api private
      attr_reader :subgraph_types_by_name_and_location

      # @api private
      attr_reader :schema_directives

      def initialize(
        query_name: "Query",
        mutation_name: "Mutation",
        subscription_name: "Subscription",
        description_merger: nil,
        deprecation_merger: nil,
        default_value_merger: nil,
        directive_kwarg_merger: nil,
        root_field_location_selector: nil
      )
        @query_name = query_name
        @mutation_name = mutation_name
        @subscription_name = subscription_name
        @description_merger = description_merger || BASIC_VALUE_MERGER
        @deprecation_merger = deprecation_merger || BASIC_VALUE_MERGER
        @default_value_merger = default_value_merger || BASIC_VALUE_MERGER
        @directive_kwarg_merger = directive_kwarg_merger || BASIC_VALUE_MERGER
        @root_field_location_selector = root_field_location_selector || BASIC_ROOT_FIELD_LOCATION_SELECTOR
        
        @field_map = {}
        @resolver_map = {}
        @resolver_configs = {}
        @mapped_type_names = {}
        @subgraph_directives_by_name_and_location = nil
        @subgraph_types_by_name_and_location = nil
        @schema_directives = nil
      end

      def perform(locations_input)
        if @subgraph_types_by_name_and_location
          raise CompositionError, "Composer may only perform once per instance."
        end

        schemas, executables = prepare_locations_input(locations_input)

        directives_to_omit = [
          GraphQL::Stitching.stitch_directive,
          KeyDirective.graphql_name,
          ResolverDirective.graphql_name,
          SourceDirective.graphql_name,
        ]

        # "directive_name" => "location" => subgraph_directive
        @subgraph_directives_by_name_and_location = schemas.each_with_object({}) do |(location, schema), memo|
          (schema.directives.keys - schema.default_directives.keys - directives_to_omit).each do |directive_name|
            memo[directive_name] ||= {}
            memo[directive_name][location] = schema.directives[directive_name]
          end
        end

        # "directive_name" => merged_directive
        @schema_directives = @subgraph_directives_by_name_and_location.each_with_object({}) do |(directive_name, directives_by_location), memo|
          memo[directive_name] = build_directive(directive_name, directives_by_location)
        end

        @schema_directives.merge!(GraphQL::Schema.default_directives)

        # "Typename" => "location" => subgraph_type
        @subgraph_types_by_name_and_location = schemas.each_with_object({}) do |(location, schema), memo|
          raise CompositionError, "Location keys must be strings" unless location.is_a?(String)

          schema.types.each do |type_name, subgraph_type|
            next if subgraph_type.introspection?

            if type_name == @query_name && subgraph_type != schema.query
              raise CompositionError, "Query name \"#{@query_name}\" is used by non-query type in #{location} schema."
            elsif type_name == @mutation_name && subgraph_type != schema.mutation
              raise CompositionError, "Mutation name \"#{@mutation_name}\" is used by non-mutation type in #{location} schema."
            elsif type_name == @subscription_name && subgraph_type != schema.subscription
              raise CompositionError, "Subscription name \"#{@subscription_name}\" is used by non-subscription type in #{location} schema."
            end

            type_name = @query_name if subgraph_type == schema.query
            type_name = @mutation_name if subgraph_type == schema.mutation
            type_name = @subscription_name if subgraph_type == schema.subscription
            @mapped_type_names[subgraph_type.graphql_name] = type_name if subgraph_type.graphql_name != type_name

            memo[type_name] ||= {}
            memo[type_name][location] = subgraph_type
          end
        end

        enum_usage = build_enum_usage_map(schemas.values)

        # "Typename" => merged_type
        schema_types = @subgraph_types_by_name_and_location.each_with_object({}) do |(type_name, types_by_location), memo|
          kinds = types_by_location.values.map { _1.kind.name }.tap(&:uniq!)

          if kinds.length > 1
            raise CompositionError, "Cannot merge different kinds for `#{type_name}`. Found: #{kinds.join(", ")}."
          end

          extract_resolvers(type_name, types_by_location) if type_name == @query_name

          memo[type_name] = case kinds.first
          when "SCALAR"
            build_scalar_type(type_name, types_by_location)
          when "ENUM"
            build_enum_type(type_name, types_by_location, enum_usage)
          when "OBJECT"
            build_object_type(type_name, types_by_location)
          when "INTERFACE"
            build_interface_type(type_name, types_by_location)
          when "UNION"
            build_union_type(type_name, types_by_location)
          when "INPUT_OBJECT"
            build_input_object_type(type_name, types_by_location)
          else
            raise CompositionError, "Unexpected kind encountered for `#{type_name}`. Found: #{kinds.first}."
          end
        end

        builder = self
        schema = Class.new(GraphQL::Schema) do
          object_types = schema_types.values.select { |t| t.respond_to?(:kind) && t.kind.object? }
          add_type_and_traverse(schema_types.values, root: false)
          orphan_types(object_types)
          query schema_types[builder.query_name]
          mutation schema_types[builder.mutation_name]
          subscription schema_types[builder.subscription_name]
          directives builder.schema_directives.values

          object_types.each do |t|
            t.interfaces.each { _1.orphan_types(t) }
          end

          own_orphan_types.clear
        end

        select_root_field_locations(schema)
        expand_abstract_resolvers(schema, schemas)
        apply_supergraph_directives(schema, @resolver_map, @field_map)

        supergraph = Supergraph.from_definition(schema, executables: executables)

        COMPOSITION_VALIDATORS.each do |validator_class|
          validator_class.new.perform(supergraph, self)
        end

        supergraph
      end

      # @!scope class
      # @!visibility private
      def prepare_locations_input(locations_input)
        schemas = {}
        executables = {}

        locations_input.each do |location, input|
          schema = input[:schema]

          if schema.nil?
            raise CompositionError, "A schema is required for `#{location}` location."
          elsif !(schema.is_a?(Class) && schema <= GraphQL::Schema)
            raise CompositionError, "The schema for `#{location}` location must be a GraphQL::Schema class."
          end

          @resolver_configs.merge!(TypeResolverConfig.extract_directive_assignments(schema, location, input[:stitch]))
          @resolver_configs.merge!(TypeResolverConfig.extract_federation_entities(schema, location))

          schemas[location.to_s] = schema
          executables[location.to_s] = input[:executable] || schema
        end

        return schemas, executables
      end

      # @!scope class
      # @!visibility private
      def build_directive(directive_name, directives_by_location)
        builder = self

        Class.new(GraphQL::Schema::Directive) do
          graphql_name(directive_name)
          description(builder.merge_descriptions(directive_name, directives_by_location))
          repeatable(directives_by_location.values.any?(&:repeatable?))
          locations(*directives_by_location.values.flat_map(&:locations).tap(&:uniq!))
          builder.build_merged_arguments(directive_name, directives_by_location, self, directive_name: directive_name)
        end
      end

      # @!scope class
      # @!visibility private
      def build_scalar_type(type_name, types_by_location)
        built_in_type = GraphQL::Schema::BUILT_IN_TYPES[type_name]
        return built_in_type if built_in_type

        builder = self

        Class.new(GraphQL::Schema::Scalar) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_enum_type(type_name, types_by_location, enum_usage)
        builder = self

        # "value" => "location" => enum_value
        enum_values_by_name_location = types_by_location.each_with_object({}) do |(location, subgraph_type), memo|
          subgraph_type.enum_values.each do |subgraph_enum_value|
            memo[subgraph_enum_value.graphql_name] ||= {}
            memo[subgraph_enum_value.graphql_name][location] = subgraph_enum_value
          end
        end

        # intersect input enum types
        if enum_usage.fetch(type_name, EMPTY_ARRAY).include?(:write)
          enum_values_by_name_location.reject! do |value, enum_values_by_location|
            types_by_location.keys.length != enum_values_by_location.keys.length
          end
        end

        Class.new(GraphQL::Schema::Enum) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))
          builder.build_merged_directives(type_name, types_by_location, self)

          enum_values_by_name_location.each do |value_name, enum_values_by_location|
            enum_value = value(value_name,
              value: value_name,
              description: builder.merge_descriptions(type_name, enum_values_by_location, enum_value: value_name),
              deprecation_reason: builder.merge_deprecations(type_name, enum_values_by_location, enum_value: value_name),
            )

            builder.build_merged_directives(type_name, enum_values_by_location, enum_value, enum_value: value_name)
          end
        end
      end

      # @!scope class
      # @!visibility private
      def build_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Object) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.tap(&:uniq!).each do |interface_name|
            implements(builder.build_type_binding(interface_name))
          end

          builder.build_merged_fields(type_name, types_by_location, self)
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_interface_type(type_name, types_by_location)
        builder = self

        Module.new do
          include GraphQL::Schema::Interface
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.tap(&:uniq!).each do |interface_name|
            implements(builder.build_type_binding(interface_name))
          end

          builder.build_merged_fields(type_name, types_by_location, self)
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_union_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Union) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          possible_names = types_by_location.values.flat_map { _1.possible_types.map(&:graphql_name) }.tap(&:uniq!)
          possible_types(*possible_names.map { builder.build_type_binding(_1) })
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_input_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::InputObject) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))
          builder.build_merged_arguments(type_name, types_by_location, self)
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      # @!scope class
      # @!visibility private
      def build_type_binding(type_name)
        GraphQL::Schema::LateBoundType.new(@mapped_type_names.fetch(type_name, type_name))
      end

      # @!scope class
      # @!visibility private
      def build_merged_fields(type_name, types_by_location, owner)
        # "field_name" => "location" => field
        fields_by_name_location = types_by_location.each_with_object({}) do |(location, subgraph_type), memo|
          @field_map[type_name] ||= {}
          subgraph_type.fields.each do |field_name, subgraph_field|
            @field_map[type_name][subgraph_field.name] ||= []
            @field_map[type_name][subgraph_field.name] << location

            memo[field_name] ||= {}
            memo[field_name][location] = subgraph_field
          end
        end

        fields_by_name_location.each do |field_name, fields_by_location|
          value_types = fields_by_location.values.map(&:type)

          type = merge_value_types(type_name, value_types, field_name: field_name)
          schema_field = owner.field(
            field_name,
            description: merge_descriptions(type_name, fields_by_location, field_name: field_name),
            deprecation_reason: merge_deprecations(type_name, fields_by_location, field_name: field_name),
            type: Util.unwrap_non_null(type),
            null: !type.non_null?,
            connection: false,
            camelize: false,
          )

          build_merged_arguments(type_name, fields_by_location, schema_field, field_name: field_name)
          build_merged_directives(type_name, fields_by_location, schema_field, field_name: field_name)
        end
      end

      # @!scope class
      # @!visibility private
      def build_merged_arguments(type_name, members_by_location, owner, field_name: nil, directive_name: nil)
        # "argument_name" => "location" => argument
        args_by_name_location = members_by_location.each_with_object({}) do |(location, subgraph_member), memo|
          subgraph_member.arguments.each do |argument_name, argument|
            memo[argument_name] ||= {}
            memo[argument_name][location] = argument
          end
        end

        args_by_name_location.each do |argument_name, arguments_by_location|
          value_types = arguments_by_location.values.map(&:type)

          if arguments_by_location.length != members_by_location.length
            if value_types.any?(&:non_null?)
              path = [type_name, field_name, argument_name].compact.join(".")
              raise CompositionError, "Required argument `#{path}` must be defined in all locations." # ...or hidden?
            end
            next
          end

          kwargs = {}
          default_values_by_location = arguments_by_location.each_with_object({}) do |(location, argument), memo|
            next if argument.default_value == NO_DEFAULT_VALUE
            memo[location] = argument.default_value
          end

          if default_values_by_location.any?
            kwargs[:default_value] = @default_value_merger.call(default_values_by_location, {
              type_name: type_name,
              field_name: field_name,
              argument_name: argument_name,
              directive_name: directive_name,
            }.tap(&:compact!))
          end

          type = merge_value_types(type_name, value_types, argument_name: argument_name, field_name: field_name)
          schema_argument = owner.argument(
            argument_name,
            description: merge_descriptions(type_name, arguments_by_location, argument_name: argument_name, field_name: field_name),
            deprecation_reason: merge_deprecations(type_name, arguments_by_location, argument_name: argument_name, field_name: field_name),
            type: Util.unwrap_non_null(type),
            required: type.non_null?,
            camelize: false,
            **kwargs,
          )

          build_merged_directives(type_name, arguments_by_location, schema_argument, field_name: field_name, argument_name: argument_name)
        end
      end

      # @!scope class
      # @!visibility private
      def build_merged_directives(type_name, members_by_location, owner, field_name: nil, argument_name: nil, enum_value: nil)
        directives_by_name_location = members_by_location.each_with_object({}) do |(location, subgraph_member), memo|
          subgraph_member.directives.each do |directive|
            memo[directive.graphql_name] ||= {}
            memo[directive.graphql_name][location] = directive
          end
        end

        directives_by_name_location.each do |directive_name, directives_by_location|
          directive_class = @schema_directives[directive_name]
          next unless directive_class

          # handled by deprecation_reason merger...
          next if directive_class.graphql_name == "deprecated"

          kwarg_values_by_name_location = directives_by_location.each_with_object({}) do |(location, directive), memo|
            directive.arguments.keyword_arguments.each do |key, value|
              key = key.to_s
              next unless directive_class.arguments[key]

              memo[key] ||= {}
              memo[key][location] = value
            end
          end

          kwargs = kwarg_values_by_name_location.each_with_object({}) do |(kwarg_name, kwarg_values_by_location), memo|
            memo[kwarg_name.to_sym] = @directive_kwarg_merger.call(kwarg_values_by_location, {
              type_name: type_name,
              field_name: field_name,
              argument_name: argument_name,
              enum_value: enum_value,
              directive_name: directive_name,
              kwarg_name: kwarg_name,
            }.tap(&:compact!))
          end

          owner.directive(directive_class, **kwargs)
        end
      end

      # @!scope class
      # @!visibility private
      def merge_value_types(type_name, subgraph_types, field_name: nil, argument_name: nil)
        path = [type_name, field_name, argument_name].tap(&:compact!).join(".")
        alt_structures = subgraph_types.map { Util.flatten_type_structure(_1) }
        basis_structure = alt_structures.shift

        alt_structures.each do |alt_structure|
          if alt_structure.length != basis_structure.length
            raise CompositionError, "Cannot compose mixed list structures at `#{path}`."
          end

          if alt_structure.last.name != basis_structure.last.name
            raise CompositionError, "Cannot compose mixed types at `#{path}`."
          end
        end

        type = GraphQL::Schema::BUILT_IN_TYPES.fetch(
          basis_structure.last.name,
          build_type_binding(basis_structure.last.name)
        )

        basis_structure.reverse!.each_with_index do |basis, index|
          rev_index = basis_structure.length - index - 1
          non_null = alt_structures.each_with_object([basis.non_null?]) { |s, m| m << s[rev_index].non_null? }

          type = type.to_list_type if basis.list?
          type = type.to_non_null_type if argument_name ? non_null.any? : non_null.all?
        end

        type
      end

      # @!scope class
      # @!visibility private
      def merge_descriptions(type_name, members_by_location, field_name: nil, argument_name: nil, enum_value: nil)
        strings_by_location = members_by_location.each_with_object({}) { |(l, m), memo| memo[l] = m.description }
        @description_merger.call(strings_by_location, {
          type_name: type_name,
          field_name: field_name,
          argument_name: argument_name,
          enum_value: enum_value,
        }.tap(&:compact!))
      end

      # @!scope class
      # @!visibility private
      def merge_deprecations(type_name, members_by_location, field_name: nil, argument_name: nil, enum_value: nil)
        strings_by_location = members_by_location.each_with_object({}) { |(l, m), memo| memo[l] = m.deprecation_reason }
        @deprecation_merger.call(strings_by_location, {
          type_name: type_name,
          field_name: field_name,
          argument_name: argument_name,
          enum_value: enum_value,
        }.tap(&:compact!))
      end

      # @!scope class
      # @!visibility private
      def extract_resolvers(type_name, types_by_location)
        types_by_location.each do |location, subgraph_type|
          subgraph_type.fields.each do |field_name, subgraph_field|
            resolver_type = subgraph_field.type.unwrap
            resolver_structure = Util.flatten_type_structure(subgraph_field.type)
            resolver_configs = @resolver_configs.fetch("#{location}.#{field_name}",  [])

            subgraph_field.directives.each do |directive|
              next unless directive.graphql_name == GraphQL::Stitching.stitch_directive
              resolver_configs << TypeResolverConfig.from_kwargs(directive.arguments.keyword_arguments)
            end

            resolver_configs.each do |config|
              resolver_type_name = if config.type_name
                if !resolver_type.kind.abstract?
                  raise CompositionError, "Type resolver config may only specify a type name for abstract resolvers."
                elsif !resolver_type.possible_types.find { _1.graphql_name == config.type_name }
                  raise CompositionError, "Type `#{config.type_name}` is not a possible return type for query `#{field_name}`."
                end
                config.type_name
              else
                resolver_type.graphql_name
              end

              key = TypeResolver.parse_key_with_types(
                config.key,
                @subgraph_types_by_name_and_location[resolver_type_name],
              )

              arguments_format = config.arguments || begin
                argument = if subgraph_field.arguments.size == 1
                  subgraph_field.arguments.values.first
                else
                  subgraph_field.arguments[key.primitive_name]
                end

                unless argument
                  raise CompositionError, "No resolver argument matched for `#{type_name}.#{field_name}`." \
                    "An argument mapping is required for unmatched names and composite keys."
                end

                "#{argument.graphql_name}: $.#{key.primitive_name}"
              end

              arguments = TypeResolver.parse_arguments_with_field(arguments_format, subgraph_field)
              arguments.each { _1.verify_key(key) }

              @resolver_map[resolver_type_name] ||= []
              @resolver_map[resolver_type_name] << TypeResolver.new(
                location: location,
                type_name: resolver_type_name,
                field: subgraph_field.name,
                list: resolver_structure.first.list?,
                key: key,
                arguments: arguments,
              )
            end
          end
        end
      end

      # @!scope class
      # @!visibility private
      def select_root_field_locations(schema)
        [schema.query, schema.mutation, schema.subscription].tap(&:compact!).each do |root_type|
          root_type.fields.each do |root_field_name, root_field|
            root_field_locations = @field_map[root_type.graphql_name][root_field_name]
            next unless root_field_locations.length > 1

            target_location = @root_field_location_selector.call(root_field_locations, {
              type_name: root_type.graphql_name,
              field_name: root_field_name,
            })
            next unless root_field_locations.include?(target_location)

            root_field_locations.reject! { _1 == target_location }
            root_field_locations.unshift(target_location)
          end
        end
      end

      # @!scope class
      # @!visibility private
      def expand_abstract_resolvers(composed_schema, schemas_by_location)
        @resolver_map.keys.each do |type_name|
          next unless composed_schema.get_type(type_name).kind.abstract?

          @resolver_map[type_name].each do |resolver|
            abstract_type = @subgraph_types_by_name_and_location[type_name][resolver.location]
            expanded_types = Util.expand_abstract_type(schemas_by_location[resolver.location], abstract_type)

            expanded_types.select { @subgraph_types_by_name_and_location[_1.graphql_name].length > 1 }.each do |impl_type|
              @resolver_map[impl_type.graphql_name] ||= []
              @resolver_map[impl_type.graphql_name].push(resolver)
            end
          end
        end
      end

      # @!scope class
      # @!visibility private
      def build_enum_usage_map(schemas)
        reads = []
        writes = []

        schemas.each do |schema|
          schema.types.each_value do |type|
            next if type.introspection?

            if type.kind.object? || type.kind.interface?
              type.fields.each_value do |field|
                field_type = field.type.unwrap
                reads << field_type.graphql_name if field_type.kind.enum?

                field.arguments.each_value do |argument|
                  argument_type = argument.type.unwrap
                  writes << argument_type.graphql_name if argument_type.kind.enum?
                end
              end

            elsif type.kind.input_object?
              type.arguments.each_value do |argument|
                argument_type = argument.type.unwrap
                writes << argument_type.graphql_name if argument_type.kind.enum?
              end
            end
          end
        end

        usage = reads.tap(&:uniq!).each_with_object({}) do |enum_name, memo|
          memo[enum_name] ||= []
          memo[enum_name] << :read
        end
        writes.tap(&:uniq!).each_with_object(usage) do |enum_name, memo|
          memo[enum_name] ||= []
          memo[enum_name] << :write
        end
      end

      def apply_supergraph_directives(schema, resolvers_by_type_name, locations_by_type_and_field)
        schema_directives = {}
        schema.types.each do |type_name, type|
          if resolvers_for_type = resolvers_by_type_name.dig(type_name)
            # Apply key directives for each unique type/key/location
            # (this allows keys to be composite selections and/or omitted from the supergraph schema)
            keys_for_type = resolvers_for_type.each_with_object({}) do |resolver, memo|
              memo[resolver.key.to_definition] ||= Set.new
              memo[resolver.key.to_definition].merge(resolver.key.locations)
            end
  
            keys_for_type.each do |key, locations|
              locations.each do |location|
                schema_directives[KeyDirective.graphql_name] ||= KeyDirective
                type.directive(KeyDirective, key: key, location: location)
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
  
              schema_directives[ResolverDirective.graphql_name] ||= ResolverDirective
              type.directive(ResolverDirective, **params.tap(&:compact!))
            end
          end
  
          next unless type.kind.fields? && !type.introspection?
  
          type.fields.each do |field_name, field|
            if field.owner != type
              # make a local copy of fields inherited from an interface
              # to assure that source attributions reflect the object, not the interface.
              field = type.field(
                field.graphql_name,
                description: field.description,
                deprecation_reason: field.deprecation_reason,
                type: Util.unwrap_non_null(field.type),
                null: !field.type.non_null?,
                connection: false,
                camelize: false,
              )
            end
            
            locations_for_field = locations_by_type_and_field.dig(type_name, field_name)
            next if locations_for_field.nil?
  
            # Apply source directives to annotate the possible locations of each field
            locations_for_field.each do |location|
              schema_directives[SourceDirective.graphql_name] ||= SourceDirective
              field.directive(SourceDirective, location: location)
            end
          end
        end
        
        schema_directives.each_value { |directive_class| schema.directive(directive_class) }
      end
    end
  end
end
