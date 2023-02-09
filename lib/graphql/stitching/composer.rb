# frozen_string_literal: true

module GraphQL
  module Stitching
    class Composer
      class ComposerError < StitchingError; end
      class ValidationError < ComposerError; end

      attr_reader :query_name, :mutation_name, :subschema_types_by_name_and_location

      DEFAULT_STRING_MERGER = ->(str_by_location, _info) { str_by_location.values.find { !_1.nil? } }

      VALIDATORS = [
        "ValidateInterfaces",
        "ValidateBoundaries",
      ].freeze

      def initialize(
        schemas:,
        query_name: "Query",
        mutation_name: "Mutation",
        description_merger: nil,
        deprecation_merger: nil
      )
        @schemas = schemas
        @query_name = query_name
        @mutation_name = mutation_name
        @field_map = {}
        @boundary_map = {}
        @mapped_type_names = {}

        @description_merger = description_merger || DEFAULT_STRING_MERGER
        @deprecation_merger = deprecation_merger || DEFAULT_STRING_MERGER
      end

      def perform
        # "Typename" => "location" => candidate_type
        @subschema_types_by_name_and_location = @schemas.each_with_object({}) do |(location, schema), memo|
          raise ComposerError, "Location keys must be strings" unless location.is_a?(String)
          raise ComposerError, "The subscription operation is not supported." if schema.subscription

          schema.types.each do |type_name, type_candidate|
            next if Supergraph::INTROSPECTION_TYPES.include?(type_name)

            if type_name == @query_name && type_candidate != schema.query
              raise ComposerError, "Query name \"#{@query_name}\" is used by non-query type in #{location} schema."
            elsif type_name == @mutation_name && type_candidate != schema.mutation
              raise ComposerError, "Mutation name \"#{@mutation_name}\" is used by non-mutation type in #{location} schema."
            end

            type_name = @query_name if type_candidate == schema.query
            type_name = @mutation_name if type_candidate == schema.mutation
            @mapped_type_names[type_candidate.graphql_name] = type_name if type_candidate.graphql_name != type_name

            memo[type_name] ||= {}
            memo[type_name][location] = type_candidate
          end
        end

        enum_usage = build_enum_usage_map(@schemas.values)

        # "Typename" => merged_type
        schema_types = @subschema_types_by_name_and_location.each_with_object({}) do |(type_name, types_by_location), memo|
          kinds = types_by_location.values.map { _1.kind.name }.uniq

          unless kinds.all? { _1 == kinds.first }
            raise ComposerError, "Cannot merge different kinds for `#{type_name}`. Found: #{kinds.join(", ")}."
          end

          memo[type_name] = case kinds.first
          when "SCALAR"
            build_scalar_type(type_name, types_by_location)
          when "ENUM"
            build_enum_type(type_name, types_by_location, enum_usage)
          when "OBJECT"
            extract_boundaries(type_name, types_by_location)
            build_object_type(type_name, types_by_location)
          when "INTERFACE"
            build_interface_type(type_name, types_by_location)
          when "UNION"
            build_union_type(type_name, types_by_location)
          when "INPUT_OBJECT"
            build_input_object_type(type_name, types_by_location)
          else
            raise ComposerError, "Unexpected kind encountered for `#{type_name}`. Found: #{kind}."
          end
        end

        builder = self
        schema = Class.new(GraphQL::Schema) do
          orphan_types schema_types.values
          query schema_types[builder.query_name]
          mutation schema_types[builder.mutation_name]

          own_orphan_types.clear
        end

        expand_abstract_boundaries(schema)

        supergraph = Supergraph.new(
          schema: schema,
          fields: @field_map,
          boundaries: @boundary_map,
          executables: @schemas,
        )

        VALIDATORS.each do |validator|
          klass = Object.const_get("GraphQL::Stitching::Composer::#{validator}")
          klass.new.perform(supergraph, self)
        end

        supergraph
      end

      def build_scalar_type(type_name, types_by_location)
        built_in_type = GraphQL::Schema::BUILT_IN_TYPES[type_name]
        return built_in_type if built_in_type

        builder = self

        Class.new(GraphQL::Schema::Scalar) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))
        end
      end

      def build_enum_type(type_name, types_by_location, enum_usage)
        builder = self

        # "value" => "location" => enum_value
        enum_values_by_value_location = types_by_location.each_with_object({}) do |(location, type_candidate), memo|
          type_candidate.enum_values.each do |enum_value_candidate|
            memo[enum_value_candidate.value] ||= {}
            memo[enum_value_candidate.value][location] ||= {}
            memo[enum_value_candidate.value][location] = enum_value_candidate
          end
        end

        # intersect input enum types
        if enum_usage.fetch(type_name, []).include?(:write)
          enum_values_by_value_location.reject! do |value, enum_values_by_location|
            types_by_location.keys.length != enum_values_by_location.keys.length
          end
        end

        Class.new(GraphQL::Schema::Enum) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          enum_values_by_value_location.each do |value, enum_values_by_location|
            value(value,
              value: value,
              description: builder.merge_descriptions(type_name, enum_values_by_location, enum_value: value),
              deprecation_reason: builder.merge_deprecations(type_name, enum_values_by_location, enum_value: value),
            )
          end
        end
      end

      def build_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Object) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.uniq.each do |interface_name|
            implements(builder.build_type_binding(interface_name))
          end

          builder.build_merged_fields(type_name, types_by_location, self)
        end
      end

      def build_interface_type(type_name, types_by_location)
        builder = self

        Module.new do
          include GraphQL::Schema::Interface
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.uniq.each do |interface_name|
            implements(builder.build_type_binding(interface_name))
          end

          builder.build_merged_fields(type_name, types_by_location, self)
        end
      end

      def build_union_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Union) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))

          possible_names = types_by_location.values.flat_map { _1.possible_types.map(&:graphql_name) }.uniq
          possible_types(*possible_names.map { builder.build_type_binding(_1) })
        end
      end

      def build_input_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::InputObject) do
          graphql_name(type_name)
          description(builder.merge_descriptions(type_name, types_by_location))
          builder.build_merged_arguments(type_name, types_by_location, self)
        end
      end

      def build_type_binding(type_name)
        GraphQL::Schema::LateBoundType.new(@mapped_type_names.fetch(type_name, type_name))
      end

      def build_merged_fields(type_name, types_by_location, owner)
        # "field_name" => "location" => field
        fields_by_name_location = types_by_location.each_with_object({}) do |(location, type_candidate), memo|
          @field_map[type_name] ||= {}
          type_candidate.fields.each do |field_name, field_candidate|
            @field_map[type_name][field_candidate.name] ||= []
            @field_map[type_name][field_candidate.name] << location

            memo[field_name] ||= {}
            memo[field_name][location] ||= {}
            memo[field_name][location] = field_candidate
          end
        end

        fields_by_name_location.each do |field_name, fields_by_location|
          value_types = fields_by_location.values.map(&:type)

          schema_field = owner.field(
            field_name,
            description: merge_descriptions(type_name, fields_by_location, field_name: field_name),
            deprecation_reason: merge_deprecations(type_name, fields_by_location, field_name: field_name),
            type: merge_value_types(type_name, value_types, field_name: field_name),
            null: !value_types.all?(&:non_null?),
            camelize: false,
          )

          build_merged_arguments(type_name, fields_by_location, schema_field, field_name: field_name)
        end
      end

      def build_merged_arguments(type_name, members_by_location, owner, field_name: nil)
        # "argument_name" => "location" => argument
        args_by_name_location = members_by_location.each_with_object({}) do |(location, member_candidate), memo|
          member_candidate.arguments.each do |argument_name, argument|
            memo[argument_name] ||= {}
            memo[argument_name][location] ||= {}
            memo[argument_name][location] = argument
          end
        end

        args_by_name_location.each do |argument_name, arguments_by_location|
          value_types = arguments_by_location.values.map(&:type)

          if arguments_by_location.length != members_by_location.length
            if value_types.any?(&:non_null?)
              path = [type_name, field_name, argument_name].compact.join(".")
              raise ComposerError, "Required argument `#{path}` must be defined in all locations." # ...or hidden?
            end
            next
          end

          # Getting double args sometimes... why?
          return if owner.arguments.any? { _1.first == argument_name }

          owner.argument(
            argument_name,
            description: merge_descriptions(type_name, arguments_by_location, argument_name: argument_name, field_name: field_name),
            deprecation_reason: merge_deprecations(type_name, arguments_by_location, argument_name: argument_name, field_name: field_name),
            type: merge_value_types(type_name, value_types, argument_name: argument_name, field_name: field_name),
            required: value_types.any?(&:non_null?),
            camelize: false,
          )
        end
      end

      def merge_value_types(type_name, type_candidates, field_name: nil, argument_name: nil)
        path = [type_name, field_name, argument_name].compact.join(".")
        named_types = type_candidates.map { Util.get_named_type(_1).graphql_name }.uniq

        unless named_types.all? { _1 == named_types.first }
          raise ComposerError, "Cannot compose mixed types at `#{path}`. Found: #{named_types.join(", ")}."
        end

        type = GraphQL::Schema::BUILT_IN_TYPES.fetch(named_types.first, build_type_binding(named_types.first))
        list_structures = type_candidates.map { Util.get_list_structure(_1) }

        if list_structures.any?(&:any?)
          if list_structures.any? { _1.length != list_structures.first.length }
            raise ComposerError, "Cannot compose mixed list structures at `#{path}`."
          end

          list_structures.each(&:reverse!)
          list_structures.first.each_with_index do |current, index|
            # input arguments use strongest nullability, readonly fields use weakest
            non_null = list_structures.public_send(argument_name ? :any? : :all?) do |list_structure|
              list_structure[index].start_with?("non_null")
            end

            case current
            when "list", "non_null_list"
              type = type.to_list_type
              type = type.to_non_null_type if non_null
            when "element", "non_null_element"
              type = type.to_non_null_type if non_null
            end
          end
        end

        type
      end

      def merge_descriptions(type_name, members_by_location, field_name: nil, argument_name: nil, enum_value: nil)
        strings_by_location = members_by_location.each_with_object({}) { |(l, m), memo| memo[l] = m.description }
        @description_merger.call(strings_by_location, {
          type_name: type_name,
          field_name: field_name,
          argument_name: argument_name,
          enum_value: enum_value,
        }.compact!)
      end

      def merge_deprecations(type_name, members_by_location, field_name: nil, argument_name: nil, enum_value: nil)
        strings_by_location = members_by_location.each_with_object({}) { |(l, m), memo| memo[l] = m.deprecation_reason }
        @deprecation_merger.call(strings_by_location, {
          type_name: type_name,
          field_name: field_name,
          argument_name: argument_name,
          enum_value: enum_value,
        }.compact!)
      end

      def extract_boundaries(type_name, types_by_location)
        types_by_location.each do |location, type_candidate|
          type_candidate.fields.each do |field_name, field_candidate|
            boundary_type_name = Util.get_named_type(field_candidate.type).graphql_name
            boundary_list = Util.get_list_structure(field_candidate.type)

            field_candidate.directives.each do |directive|
              next unless directive.graphql_name == GraphQL::Stitching.stitch_directive

              key = directive.arguments.keyword_arguments.fetch(:key)
              key_selections = GraphQL.parse("{ #{key} }").definitions[0].selections

              if key_selections.length != 1
                raise ComposerError, "Boundary key at #{type_name}.#{field_name} must specify exactly one key."
              end

              argument_name = key_selections[0].alias
              argument_name ||= if field_candidate.arguments.size == 1
                field_candidate.arguments.keys.first
              end

              argument = field_candidate.arguments[argument_name]
              unless argument
                # contextualize this... "boundaries with multiple args need mapping aliases."
                raise ComposerError, "Invalid boundary argument `#{argument_name}` for #{type_name}.#{field_name}."
              end

              argument_list = Util.get_list_structure(argument.type)
              if argument_list.length != boundary_list.length
                raise ComposerError, "Mismatched input/output for #{type_name}.#{field_name}.#{argument_name} boundary. Arguments must map directly to results."
              end

              @boundary_map[boundary_type_name] ||= []
              @boundary_map[boundary_type_name] << {
                "location" => location,
                "selection" => key_selections[0].name,
                "field" => field_candidate.name,
                "arg" => argument_name,
                "list" => boundary_list.any?,
                "type_name" => boundary_type_name,
              }
            end
          end
        end
      end

      def expand_abstract_boundaries(schema)
        @boundary_map.keys.each do |type_name|
          boundary_type = schema.types[type_name]
          next unless boundary_type.kind.abstract?

          possible_types = Util.get_possible_types(schema, boundary_type)
          possible_types.select { @subschema_types_by_name_and_location[_1.graphql_name].length > 1 }.each do |possible_type|
            @boundary_map[possible_type.graphql_name] ||= []
            @boundary_map[possible_type.graphql_name].push(*@boundary_map[type_name])
          end
        end
      end

      def build_enum_usage_map(schemas)
        reads = []
        writes = []

        schemas.each do |schema|
          schema.types.values.each do |type|
            next if Supergraph::INTROSPECTION_TYPES.include?(type.graphql_name)

            if type.kind.object? || type.kind.interface?
              type.fields.values.each do |field|
                field_type = Util.get_named_type(field.type)
                reads << field_type.graphql_name if field_type.kind.enum?

                field.arguments.values.each do |argument|
                  argument_type = Util.get_named_type(argument.type)
                  writes << argument_type.graphql_name if argument_type.kind.enum?
                end
              end

            elsif type.kind.input_object?
              type.arguments.values.each do |argument|
                argument_type = Util.get_named_type(argument.type)
                writes << argument_type.graphql_name if argument_type.kind.enum?
              end
            end
          end
        end

        usage = reads.uniq.each_with_object({}) do |enum_name, memo|
          memo[enum_name] ||= []
          memo[enum_name] << :read
        end
        writes.uniq.each_with_object(usage) do |enum_name, memo|
          memo[enum_name] ||= []
          memo[enum_name] << :write
        end
      end
    end
  end
end

require_relative "./composer/base_validator"
require_relative "./composer/validate_interfaces"
require_relative "./composer/validate_boundaries"
