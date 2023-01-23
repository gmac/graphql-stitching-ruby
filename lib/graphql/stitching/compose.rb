# frozen_string_literal: true

module GraphQL
  module Stitching
    class Compose

      attr_reader :query_name, :mutation_name

      def initialize(schemas:, query_name: "Query", mutation_name: "Mutation")
        @schemas = schemas
        @query_name = query_name
        @mutation_name = mutation_name
        @field_map = {}
      end

      def compose
        type_candidates_map = @schemas.each_with_object({}) do |(location, schema), memo|
          schema.types.each do |typename, type|
            next if typename.start_with?("__")

            if typename == @query_name && type != schema.query
              raise "Root query name \"#{@query_name}\" is used by non-query type in #{location} schema."
            elsif typename == @mutation_name && type != schema.mutation
              raise "Root mutation name \"#{@mutation_name}\" is used by non-mutation type in #{location} schema."
            end

            typename = @query_name if type == schema.query
            typename = @mutation_name if type == schema.mutation

            memo[typename] ||= {}
            memo[typename][location] = type
          end
        end

        types = type_candidates_map.each_with_object({}) do |(typename, types_by_location), memo|
          kinds = types_by_location.values.map { _1.kind.name }.uniq

          unless kinds.all? { _1 == kinds.first }
            raise "Cannot merge different kinds for #{typename}, found: #{kinds.join(", ")}."
          end

          memo[typename] = case kinds.first
          when "SCALAR"
            build_scalar_type(typename, types_by_location)
          when "ENUM"
            build_enum_type(typename, types_by_location)
          when "OBJECT"
            build_object_type(typename, types_by_location)
          when "INTERFACE"
            build_interface_type(typename, types_by_location)
          when "UNION"
            build_union_type(typename, types_by_location)
          when "INPUT_OBJECT"
            build_input_object_type(typename, types_by_location)
          else
            raise "Unexpected kind encountered for #{typename}, found: #{kind}."
          end
        end

        schema = Class.new(GraphQL::Schema) do
          orphan_types types.values
        end

        # do these after class constructor so the root types resolve
        schema.query(schema.types[@query_name])
        schema.mutation(schema.types[@mutation_name])
        schema.send(:own_orphan_types).clear # cheat
        schema
      end

      def build_scalar_type(typename, types_by_location)
        built_in_type = GraphQL::Schema::BUILT_IN_TYPES[typename]
        return built_in_type if built_in_type

        builder = self

        Class.new(GraphQL::Schema::Scalar) do
          graphql_name(typename)
          description(builder.merge_descriptions(types_by_location))
        end
      end

      def build_enum_type(typename, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Enum) do
          graphql_name(typename)
          description(builder.merge_descriptions(types_by_location))

          # locations_by_value = {}
          enum_values_by_value = {}
          types_by_location.each do |location, type_candidate|
            type_candidate.enum_values.each do |enum_value_candidate|
              # locations_by_value[enum_value.value] ||= []
              # locations_by_value[enum_value.value] << location
              enum_values_by_value[enum_value_candidate.value] ||= []
              enum_values_by_value[enum_value_candidate.value] << enum_value_candidate
            end
          end

          enum_values_by_value.each do |value, locations|
            value(value,
              value: value,
              # deprecation_reason: "tktk"
              # description: enum_value_definition.description,
            )
          end
        end
      end

      def build_object_type(typename, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Object) do
          graphql_name(typename)
          description(builder.merge_descriptions(types_by_location))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.uniq.each do |interface_name|
            implements(GraphQL::Schema::LateBoundType.new(interface_name))
          end

          builder.build_merged_fields(typename, types_by_location, self)
        end
      end

      def build_interface_type(typename, types_by_location)
        builder = self

        Module.new do
          include GraphQL::Schema::Interface
          graphql_name(typename)
          description(builder.merge_descriptions(types_by_location))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.uniq.each do |interface_name|
            implements(GraphQL::Schema::LateBoundType.new(interface_name))
          end

          builder.build_merged_fields(typename, types_by_location, self)
        end
      end

      def build_union_type(typename, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Union) do
          graphql_name(typename)
          description(builder.merge_descriptions(types_by_location))

          possible_names = types_by_location.values.flat_map { _1.possible_types.map(&:graphql_name) }
          possible_types *possible_names.map { GraphQL::Schema::LateBoundType.new(_1) }
        end
      end

      def build_input_object_type(typename, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::InputObject) do
          graphql_name(typename)
          description(builder.merge_descriptions(types_by_location))
          # builder.build_arguments(self, input_object_type_definition.fields, type_resolver)
        end
      end

      def build_merged_fields(typename, types_by_location, owner)
        fields_by_name = types_by_location.each_with_object({}) do |(location, type_candidate), memo|
          @field_map[typename] ||= {}
          type_candidate.fields.each do |fieldname, field|
            @field_map[typename][field.name] ||= []
            @field_map[typename][field.name] << location

            memo[fieldname] ||= []
            memo[fieldname] << field
          end
        end

        fields_by_name.each do |fieldname, field_candidates|
          field_types = field_candidates.map(&:type)

          schema_field = owner.field(
            fieldname,
            description: "tktk",
            type: build_merged_wrapped_type(field_types, "#{typename}.#{fieldname}"),
            null: !field_types.all?(&:non_null?),
            # deprecation_reason: "tktk",
            camelize: false,
          )

          arguments_by_name = field_candidates.each_with_object({}) do |field_candidate, memo|
            field_candidate.arguments.each do |argname, argument|
              memo[argname] ||= []
              memo[argname] << argument
            end
          end

          arguments_by_name.each do |argname, argument_candidates|
            build_merged_arguments(typename, fieldname, argname, argument_candidates, schema_field)
          end
        end
      end

      def build_merged_arguments(typename, fieldname, argname, argument_candidates, owner)
        argument_types = argument_candidates.map(&:type)

        owner.argument(
          argname,
          description: "tktk",
          type: build_merged_wrapped_type(argument_types, "#{typename}.#{fieldname}(#{argname})"),
          required: argument_types.any?(&:non_null?),
          # deprecation_reason: "tktk",
          camelize: false,
        )
      end

      def build_merged_wrapped_type(type_candidates, path)
        named_types = type_candidates.map { Util.get_named_type(_1).graphql_name }.uniq

        unless named_types.all? { _1 == named_types.first }
          raise "Cannot compose mixed types at #{path}, found: #{named_types.join(", ")}."
        end

        list_structures = type_candidates.map { Util.get_list_structure(_1) }
        is_list = list_structures.any?(&:any?)

        if is_list && list_structures.all? { _1[0..-2] != list_structures.first[0..-2] }
          raise "Cannot compose mixed list structures at #{path}."
        end

        type = GraphQL::Schema::BUILT_IN_TYPES.fetch(
          named_types.first,
          GraphQL::Schema::LateBoundType.new(named_types.first)
        )

        if is_list
          if list_structures.all? { _1.last == GraphQL::Schema::NonNull }
            type = type.to_non_null_type
          end
          list_structures.first[0..-2].reverse!.each do |wrapper|
            case wrapper.name
            when "GraphQL::Schema::List"
              type = type.to_list_type
            when "GraphQL::Schema::NonNull"
              type = type.to_non_null_type
            end
          end
        end

        type
      end

      def merge_descriptions(types_by_location)
        # types_by_location.each_with_object({}) { |(l, t), m| m[l] = t.description }
        types_by_location.values.map(&:description).find { !_1.nil? }
      end
    end
  end
end
