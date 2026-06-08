# frozen_string_literal: true
# typed: true

require_relative "composer/base_validator"
require_relative "composer/validate_interfaces"
require_relative "composer/validate_type_resolvers"
require_relative "composer/type_resolver_config"

module GraphQL
  module Stitching
    class Composer
      NO_DEFAULT_VALUE = begin
        t = Class.new(GraphQL::Schema::Object) do
          field(:f, String) { _1.argument(:a, String) }
        end

        t.get_field("f").get_argument("a").default_value
      end

      BASIC_VALUE_MERGER = ->(values_by_location, _info) { values_by_location.values.find { !_1.nil? } }

      VISIBILITY_PROFILES_MERGER = ->(values_by_location, _info) { values_by_location.values.reduce(:&) }

      COMPOSITION_VALIDATORS = [
        ValidateInterfaces,
        ValidateTypeResolvers,
      ].freeze

      #: TypeName
      attr_reader :query_name

      #: TypeName
      attr_reader :mutation_name

      #: TypeName
      attr_reader :subscription_name

      #: Hash[TypeName, Hash[Location, untyped]]?
      attr_reader :subgraph_types_by_name_and_location

      #: Hash[String, untyped]?
      attr_reader :schema_directives

      #: (
      #|   ?query_name: TypeName,
      #|   ?mutation_name: TypeName,
      #|   ?subscription_name: TypeName,
      #|   ?visibility_profiles: Array[String],
      #|   ?description_merger: untyped,
      #|   ?deprecation_merger: untyped,
      #|   ?default_value_merger: untyped,
      #|   ?directive_kwarg_merger: untyped,
      #|   ?root_field_location_selector: untyped,
      #|   ?root_entrypoints: Hash[String, Location]?
      #| ) -> void
      def initialize(
        query_name: "Query",
        mutation_name: "Mutation",
        subscription_name: "Subscription",
        visibility_profiles: [],
        description_merger: nil,
        deprecation_merger: nil,
        default_value_merger: nil,
        directive_kwarg_merger: nil,
        root_field_location_selector: nil,
        root_entrypoints: nil
      )
        @query_name = query_name
        @mutation_name = mutation_name
        @subscription_name = subscription_name
        @description_merger = description_merger || BASIC_VALUE_MERGER #: untyped
        @deprecation_merger = deprecation_merger || BASIC_VALUE_MERGER #: untyped
        @default_value_merger = default_value_merger || BASIC_VALUE_MERGER #: untyped
        @directive_kwarg_merger = directive_kwarg_merger || BASIC_VALUE_MERGER #: untyped
        @root_field_location_selector = root_field_location_selector #: untyped
        @root_entrypoints = root_entrypoints || {} #: Hash[String, Location]
        
        @field_map = {} #: LocationsByTypeAndField
        @resolver_map = {} #: TypeResolverMap
        @resolver_configs = {} #: Hash[String, Array[TypeResolverConfig]]
        @mapped_type_names = {} #: Hash[TypeName, TypeName]
        @visibility_profiles = Set.new(visibility_profiles) #: Set[String]
        @subgraph_directives_by_name_and_location = nil #: Hash[String, Hash[Location, untyped]]?
        @subgraph_types_by_name_and_location = nil #: Hash[TypeName, Hash[Location, untyped]]?
        @schema_directives = nil #: Hash[String, untyped]?
      end

      #: (Hash[Location | Symbol, Hash[Symbol, untyped]] locations_input) -> Supergraph
      def perform(locations_input)
        if @subgraph_types_by_name_and_location
          raise CompositionError, "Composer may only perform once per instance."
        end

        schemas, executables = prepare_locations_input(locations_input)

        directives_to_omit = [
          GraphQL::Stitching.stitch_directive,
          Directives::SupergraphKey.graphql_name,
          Directives::SupergraphResolver.graphql_name,
          Directives::SupergraphSource.graphql_name,
        ]

        # "directive_name" => "location" => subgraph_directive
        subgraph_directives_by_name_and_location = schemas.each_with_object({}) do |(location, schema), memo|
          (schema.directives.keys - schema.default_directives.keys - directives_to_omit).each do |directive_name|
            memo[directive_name] ||= {}
            memo[directive_name][location] = schema.directives[directive_name]
          end
        end
        @subgraph_directives_by_name_and_location = subgraph_directives_by_name_and_location

        # "directive_name" => merged_directive
        schema_directives = subgraph_directives_by_name_and_location.each_with_object({}) do |(directive_name, directives_by_location), memo|
          memo[directive_name] = build_directive(directive_name, directives_by_location)
        end

        schema_directives.merge!(GraphQL::Schema.default_directives)
        @schema_directives = schema_directives

        # "Typename" => "location" => subgraph_type
        subgraph_types_by_name_and_location = schemas.each_with_object({}) do |(location, schema), memo|
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
        @subgraph_types_by_name_and_location = subgraph_types_by_name_and_location

        enum_usage = build_enum_usage_map(schemas.values)

        # "Typename" => merged_type
        schema_types = subgraph_types_by_name_and_location.each_with_object({}) do |(type_name, types_by_location), memo|
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
          directives schema_directives.values

          object_types.each do |t|
            t.interfaces.each { _1.orphan_types(t) }
          end

          own_orphan_types.clear
        end

        select_root_field_locations(schema)
        expand_abstract_resolvers(schema, schemas)
        apply_supergraph_directives(schema, @resolver_map, @field_map)

        if (visibility_def = schema.directives[GraphQL::Stitching.visibility_directive])
          visibility_def.get_argument("profiles").default_value(@visibility_profiles.to_a.sort)
        end

        supergraph = Supergraph.from_definition(schema, executables: executables)

        COMPOSITION_VALIDATORS.each do |validator_class|
          validator_class.new.perform(supergraph, self)
        end

        supergraph
      end

      #: (Hash[Location | Symbol, Hash[Symbol, untyped]] locations_input) -> [Hash[Location, singleton(GraphQL::Schema)], Hash[Location, Executable]]
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

          location = location.to_s
          @resolver_configs.merge!(TypeResolverConfig.extract_directive_assignments(schema, location, input[:stitch]))
          @resolver_configs.merge!(TypeResolverConfig.extract_federation_entities(schema, location))

          schemas[location] = schema
          executables[location] = input[:executable] || schema
        end

        return schemas, executables
      end

      #: (String directive_name, Hash[Location, untyped] directives_by_location) -> untyped
      def build_directive(directive_name, directives_by_location)
        builder = self

        Class.new(GraphQL::Schema::Directive) do
          graphql_name(directive_name)
          description(builder.merged_description(directive_name, directives_by_location))
          repeatable(directives_by_location.values.any?(&:repeatable?))
          builder.apply_directive_locations(self, directives_by_location)
          builder.build_merged_arguments(directive_name, directives_by_location, self, directive_name: directive_name)
        end
      end

      #: (Hash[Location, untyped] directives_by_location) -> Array[untyped]
      def merged_directive_locations(directives_by_location)
        directives_by_location.values.flat_map(&:locations).tap(&:uniq!)
      end

      #: (untyped directive_class, Hash[Location, untyped] directives_by_location) -> void
      def apply_directive_locations(directive_class, directives_by_location)
        directive_class.locations(*merged_directive_locations(directives_by_location))
      end

      #: (TypeName type_name, Hash[Location, untyped] types_by_location) -> untyped
      def build_scalar_type(type_name, types_by_location)
        built_in_type = GraphQL::Schema::BUILT_IN_TYPES[type_name]
        return built_in_type if built_in_type

        builder = self

        Class.new(GraphQL::Stitching::Supergraph::ScalarType) do
          graphql_name(type_name)
          description(builder.merged_description(type_name, types_by_location))
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      #: (TypeName type_name, Hash[Location, untyped] types_by_location, Hash[TypeName, Array[Symbol]] enum_usage) -> untyped
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

        Class.new(GraphQL::Stitching::Supergraph::EnumType) do
          graphql_name(type_name)
          description(builder.merged_description(type_name, types_by_location))
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

      #: (TypeName type_name, Hash[Location, untyped] types_by_location) -> untyped
      def build_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Stitching::Supergraph::ObjectType) do
          graphql_name(type_name)
          description(builder.merged_description(type_name, types_by_location))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.tap(&:uniq!).each do |interface_name|
            implements(builder.build_type_binding(interface_name))
          end

          builder.build_merged_fields(type_name, types_by_location, self)
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      #: (TypeName type_name, Hash[Location, untyped] types_by_location) -> untyped
      def build_interface_type(type_name, types_by_location)
        builder = self

        interface_type = Module.new #: untyped
        interface_type.include GraphQL::Stitching::Supergraph::InterfaceType
        interface_type.graphql_name(type_name)
        interface_type.description(builder.merged_description(type_name, types_by_location))

        interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
        interface_names.tap(&:uniq!).each do |interface_name|
          interface_type.implements(builder.build_type_binding(interface_name))
        end

        builder.build_merged_fields(type_name, types_by_location, interface_type)
        builder.build_merged_directives(type_name, types_by_location, interface_type)

        interface_type
      end

      #: (TypeName type_name, Hash[Location, untyped] types_by_location) -> untyped
      def build_union_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Stitching::Supergraph::UnionType) do
          graphql_name(type_name)
          description(builder.merged_description(type_name, types_by_location))

          possible_names = types_by_location.values.flat_map { _1.possible_types.map(&:graphql_name) }.tap(&:uniq!)
          builder.apply_possible_types(self, possible_names)
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      #: (TypeName type_name, Hash[Location, untyped] types_by_location) -> untyped
      def build_input_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Stitching::Supergraph::InputObjectType) do
          graphql_name(type_name)
          description(builder.merged_description(type_name, types_by_location))
          builder.build_merged_arguments(type_name, types_by_location, self)
          builder.build_merged_directives(type_name, types_by_location, self)
        end
      end

      #: (TypeName type_name) -> GraphQL::Schema::LateBoundType
      def build_type_binding(type_name)
        GraphQL::Schema::LateBoundType.new(@mapped_type_names.fetch(type_name, type_name))
      end

      #: (Array[TypeName] possible_names) -> Array[GraphQL::Schema::LateBoundType]
      def possible_type_bindings(possible_names)
        possible_names.map { build_type_binding(_1) }
      end

      #: (untyped union_type, Array[TypeName] possible_names) -> void
      def apply_possible_types(union_type, possible_names)
        union_type.possible_types(*possible_type_bindings(possible_names))
      end

      #: (TypeName type_name, Hash[Location, untyped] types_by_location, untyped owner) -> void
      def build_merged_fields(type_name, types_by_location, owner)
        # "field_name" => "location" => field
          field_locations_by_name = @field_map[type_name] ||= {}
          fields_by_name_location = types_by_location.each_with_object({}) do |(location, subgraph_type), memo|
            subgraph_type.fields.each do |field_name, subgraph_field|
              field_locations_by_name[subgraph_field.name] ||= []
              field_locations_by_name.fetch(subgraph_field.name) << location

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

      #: (
      #|   TypeName type_name,
      #|   Hash[Location, untyped] members_by_location,
      #|   untyped owner,
      #|   ?field_name: FieldName?,
      #|   ?directive_name: String?
      #| ) -> void
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

          unless default_values_by_location.empty?
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

      #: (
      #|   TypeName type_name,
      #|   Hash[Location, untyped] members_by_location,
      #|   untyped owner,
      #|   ?field_name: FieldName?,
      #|   ?argument_name: String?,
      #|   ?enum_value: String?
      #| ) -> void
      def build_merged_directives(type_name, members_by_location, owner, field_name: nil, argument_name: nil, enum_value: nil)
        directives_by_name_location = members_by_location.each_with_object({}) do |(location, subgraph_member), memo|
          subgraph_member.directives.each do |directive|
            memo[directive.graphql_name] ||= {}
            memo[directive.graphql_name][location] = directive
          end
        end

        directives_by_name_location.each do |directive_name, directives_by_location|
          kwarg_merger = @directive_kwarg_merger
          directive_class = @schema_directives&.[](directive_name)
          next unless directive_class

          # handled by deprecation_reason merger...
          next if directive_class.graphql_name == "deprecated"

          kwarg_values_by_name_location = directives_by_location.each_with_object({}) do |(location, directive), memo|
            directive.arguments.keyword_arguments.each do |key, value|
              key = key.to_s
              memo[key] ||= {}
              memo[key][location] = value
            end
          end

          if directive_class.graphql_name == GraphQL::Stitching.visibility_directive
            unless GraphQL::Stitching.supports_visibility?
              raise CompositionError, "Using `@#{GraphQL::Stitching.visibility_directive}` directive " \
                "for schema visibility controls requires GraphQL Ruby v#{GraphQL::Stitching::MIN_VISIBILITY_VERSION} or later."
            end

            if (profiles = kwarg_values_by_name_location["profiles"])
              @visibility_profiles.merge(profiles.each_value.reduce(&:|))
              kwarg_merger = VISIBILITY_PROFILES_MERGER
            end
          end

          kwargs = kwarg_values_by_name_location.each_with_object({}) do |(kwarg_name, kwarg_values_by_location), memo|
            memo[kwarg_name.to_sym] = kwarg_merger.call(kwarg_values_by_location, {
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

      #: (TypeName type_name, Array[untyped] subgraph_types, ?field_name: FieldName?, ?argument_name: String?) -> untyped
      def merge_value_types(type_name, subgraph_types, field_name: nil, argument_name: nil)
        path = [type_name, field_name, argument_name].tap(&:compact!).join(".")
        alt_structures = subgraph_types.map { Util.flatten_type_structure(_1) }
        basis_structure = alt_structures.fetch(0)
        alt_structures = alt_structures.drop(1)

        alt_structures.each do |alt_structure|
          if alt_structure.length != basis_structure.length
            raise CompositionError, "Cannot compose mixed list structures at `#{path}`."
          end

          if alt_structure.fetch(-1).name != basis_structure.fetch(-1).name
            raise CompositionError, "Cannot compose mixed types at `#{path}`."
          end
        end

        type_name = basis_structure.fetch(-1).name
        raise CompositionError, "Cannot compose unnamed type at `#{path}`." unless type_name

        type = GraphQL::Schema::BUILT_IN_TYPES.fetch(
          type_name,
          build_type_binding(type_name)
        )

        basis_structure.reverse!.each_with_index do |basis, index|
          rev_index = basis_structure.length - index - 1
          non_null = alt_structures.each_with_object([basis.non_null?]) { |s, m| m << s.fetch(rev_index).non_null? }

          type = type.to_list_type if basis.list?
          type = type.to_non_null_type if argument_name ? non_null.any? : non_null.all?
        end

        type
      end

      #: (TypeName type_name, Hash[Location, untyped] members_by_location, ?field_name: FieldName?, ?argument_name: String?, ?enum_value: String?) -> String?
      def merge_descriptions(type_name, members_by_location, field_name: nil, argument_name: nil, enum_value: nil)
        strings_by_location = members_by_location.each_with_object({}) { |(l, m), memo| memo[l] = m.description }
        @description_merger.call(strings_by_location, {
          type_name: type_name,
          field_name: field_name,
          argument_name: argument_name,
          enum_value: enum_value,
        }.tap(&:compact!))
      end

      #: (TypeName type_name, Hash[Location, untyped] members_by_location, ?field_name: FieldName?, ?argument_name: String?, ?enum_value: String?) -> String
      def merged_description(type_name, members_by_location, field_name: nil, argument_name: nil, enum_value: nil)
        merge_descriptions(
          type_name,
          members_by_location,
          field_name: field_name,
          argument_name: argument_name,
          enum_value: enum_value,
        ).to_s
      end

      #: (TypeName type_name, Hash[Location, untyped] members_by_location, ?field_name: FieldName?, ?argument_name: String?, ?enum_value: String?) -> String?
      def merge_deprecations(type_name, members_by_location, field_name: nil, argument_name: nil, enum_value: nil)
        strings_by_location = members_by_location.each_with_object({}) { |(l, m), memo| memo[l] = m.deprecation_reason }
        @deprecation_merger.call(strings_by_location, {
          type_name: type_name,
          field_name: field_name,
          argument_name: argument_name,
          enum_value: enum_value,
        }.tap(&:compact!))
      end

      #: (TypeName type_name, Hash[Location, untyped] types_by_location) -> void
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

              subgraph_types_by_name_and_location = @subgraph_types_by_name_and_location
              raise CompositionError, "Composer has no subgraph types." unless subgraph_types_by_name_and_location

              key = TypeResolver.parse_key_with_types(
                config.key,
                subgraph_types_by_name_and_location.fetch(resolver_type_name),
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
              @resolver_map.fetch(resolver_type_name) << TypeResolver.new(
                location: location,
                type_name: resolver_type_name,
                field: subgraph_field.name,
                list: resolver_structure.fetch(0).list?,
                key: key,
                arguments: arguments,
              )
            end
          end
        end
      end

      #: (singleton(GraphQL::Schema) schema) -> void
      def select_root_field_locations(schema)
        [schema.query, schema.mutation, schema.subscription].tap(&:compact!).each do |root_type|
          root_type.fields.each do |root_field_name, root_field|
            root_field_locations = @field_map.fetch(root_type.graphql_name).fetch(root_field_name)
            next unless root_field_locations.length > 1

            root_field_path = "#{root_type.graphql_name}.#{root_field_name}"
            target_location = if @root_field_location_selector && @root_entrypoints.empty?
              Warning.warn("Composer option `root_field_location_selector` is deprecated and will be removed.")
              @root_field_location_selector.call(root_field_locations, {
                type_name: root_type.graphql_name,
                field_name: root_field_name,
              })
            else
              @root_entrypoints[root_field_path] || root_field_locations.last
            end

            unless root_field_locations.include?(target_location)
              raise CompositionError, "Invalid `root_entrypoints` configuration: `#{root_field_path}` has no `#{target_location}` location."
            end

            root_field_locations.reject! { _1 == target_location }
            root_field_locations.unshift(target_location)
          end
        end
      end

      #: (singleton(GraphQL::Schema) composed_schema, Hash[Location, singleton(GraphQL::Schema)] schemas_by_location) -> void
      def expand_abstract_resolvers(composed_schema, schemas_by_location)
        @resolver_map.keys.each do |type_name|
          next unless composed_schema.get_type(type_name).kind.abstract?

          @resolver_map.fetch(type_name).each do |resolver|
            subgraph_types_by_name_and_location = @subgraph_types_by_name_and_location
            raise CompositionError, "Composer has no subgraph types." unless subgraph_types_by_name_and_location

            abstract_type = subgraph_types_by_name_and_location.fetch(type_name).fetch(resolver.location)
            expanded_types = expand_abstract_type(schemas_by_location.fetch(resolver.location), abstract_type)

            expanded_types.select { subgraph_types_by_name_and_location.fetch(_1.graphql_name).length > 1 }.each do |impl_type|
              @resolver_map[impl_type.graphql_name] ||= []
              @resolver_map.fetch(impl_type.graphql_name).push(resolver)
            end
          end
        end
      end

      #: (singleton(GraphQL::Schema) schema, untyped parent_type) -> Array[CompositeType]
      def expand_abstract_type(schema, parent_type)
        return EMPTY_ARRAY unless parent_type.kind.abstract?
        return parent_type.possible_types if parent_type.kind.union?

        child_interfaces_by_parent = Hash.new { |hash, key| hash[key] = [] }
        schema.types.each_value do |schema_type|
          type = schema_type #: untyped
          next unless type <= GraphQL::Schema::Interface && type != parent_type

          type.public_send(:interfaces).each do |interface_type|
            child_interfaces_by_parent[interface_type] << type
          end
        end

        result = schema.possible_types(parent_type)
        pending = child_interfaces_by_parent[parent_type].dup

        until pending.empty?
          type = pending.shift
          next if result.include?(type)

          result << type
          pending.concat(child_interfaces_by_parent[type])
        end

        result
      end

      #: (Array[singleton(GraphQL::Schema)] schemas) -> Hash[TypeName, Array[Symbol]]
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

      #: (singleton(GraphQL::Schema) schema, TypeResolverMap resolvers_by_type_name, LocationsByTypeAndField locations_by_type_and_field) -> void
      def apply_supergraph_directives(schema, resolvers_by_type_name, locations_by_type_and_field)
        schema_directives = {}
        schema.types.each do |type_name, type|
          if resolvers_for_type = resolvers_by_type_name.dig(type_name)
            # Apply key directives for each unique type/key/location
            # (this allows keys to be composite selections and/or omitted from the supergraph schema)
            keys_for_type = resolvers_for_type.each_with_object({}) do |resolver, memo|
              resolver_key = resolver.key
              raise CompositionError, "Missing key for resolver on `#{type_name}`." unless resolver_key

              memo[resolver_key.to_definition] ||= Set.new
              memo[resolver_key.to_definition].merge(resolver_key.locations)
            end
  
            keys_for_type.each do |key, locations|
              locations.each do |location|
                schema_directives[Directives::SupergraphKey.graphql_name] ||= Directives::SupergraphKey
                type.directive(Directives::SupergraphKey, key: key, location: location)
              end
            end
  
            # Apply resolver directives for each unique query resolver
            resolvers_for_type.each do |resolver|
              resolver_key = resolver.key
              raise CompositionError, "Missing key for resolver on `#{type_name}`." unless resolver_key

              params = {
                location: resolver.location,
                field: resolver.field,
                list: resolver.list? || nil,
                key: resolver_key.to_definition,
                arguments: resolver.arguments.map(&:to_definition).join(", "),
                argument_types: resolver.arguments.map(&:to_type_definition).join(", "),
                type_name: (resolver.type_name if resolver.type_name != type_name),
              }
  
              schema_directives[Directives::SupergraphResolver.graphql_name] ||= Directives::SupergraphResolver
              type.directive(Directives::SupergraphResolver, **params.tap(&:compact!))
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
              schema_directives[Directives::SupergraphSource.graphql_name] ||= Directives::SupergraphSource
              field.directive(Directives::SupergraphSource, location: location)
            end
          end
        end
        
        schema_directives.each_value { |directive_class| schema.directive(directive_class) }
      end
    end
  end
end
