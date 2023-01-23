# frozen_string_literal: true

module GraphQL
  module Stitching
    class Compose

      attr_reader :query_name, :mutation_name
      attr_reader :field_map, :boundary_map

      def initialize(schemas:, query_name: "Query", mutation_name: "Mutation")
        @schemas = schemas
        @query_name = query_name
        @mutation_name = mutation_name
        @field_map = {}
        @boundary_map = {}
      end

      def compose
        # "Typename" => "location" => candidate_type
        type_candidates_map = @schemas.each_with_object({}) do |(location, schema), memo|
          schema.types.each do |type_name, type_candidate|
            next if type_name.start_with?("__")

            if type_name == @query_name && type_candidate != schema.query
              raise "Root query name \"#{@query_name}\" is used by non-query type in #{location} schema."
            elsif type_name == @mutation_name && type_candidate != schema.mutation
              raise "Root mutation name \"#{@mutation_name}\" is used by non-mutation type in #{location} schema."
            end

            type_name = @query_name if type_candidate == schema.query
            type_name = @mutation_name if type_candidate == schema.mutation

            memo[type_name] ||= {}
            memo[type_name][location] = type_candidate
          end
        end

        # "Typename" => merged_type
        schema_types = type_candidates_map.each_with_object({}) do |(type_name, types_by_location), memo|
          kinds = types_by_location.values.map { _1.kind.name }.uniq

          unless kinds.all? { _1 == kinds.first }
            raise "Cannot merge different kinds for #{type_name}, found: #{kinds.join(", ")}."
          end

          memo[type_name] = case kinds.first
          when "SCALAR"
            build_scalar_type(type_name, types_by_location)
          when "ENUM"
            build_enum_type(type_name, types_by_location)
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
            raise "Unexpected kind encountered for #{type_name}, found: #{kind}."
          end
        end

        schema = Class.new(GraphQL::Schema) do
          orphan_types schema_types.values
        end

        # do these after class constructor so the root types resolve
        schema.query(schema.types[@query_name])
        schema.mutation(schema.types[@mutation_name])
        schema.send(:own_orphan_types).clear # cheat
        return schema, {
          fields: @field_map,
          boundaries: @boundary_map,
        }
      end

      def build_scalar_type(type_name, types_by_location)
        built_in_type = GraphQL::Schema::BUILT_IN_TYPES[type_name]
        return built_in_type if built_in_type

        builder = self

        Class.new(GraphQL::Schema::Scalar) do
          graphql_name(type_name)
          description(builder.merge_descriptions(types_by_location, type_name))
        end
      end

      def build_enum_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Enum) do
          graphql_name(type_name)
          description(builder.merge_descriptions(types_by_location, type_name))

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

      def build_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Object) do
          graphql_name(type_name)
          description(builder.merge_descriptions(types_by_location, type_name))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.uniq.each do |interface_name|
            implements(GraphQL::Schema::LateBoundType.new(interface_name))
          end

          builder.build_merged_fields(self, type_name, types_by_location)
        end
      end

      def build_interface_type(type_name, types_by_location)
        builder = self

        Module.new do
          include GraphQL::Schema::Interface
          graphql_name(type_name)
          description(builder.merge_descriptions(types_by_location, type_name))

          interface_names = types_by_location.values.flat_map { _1.interfaces.map(&:graphql_name) }
          interface_names.uniq.each do |interface_name|
            implements(GraphQL::Schema::LateBoundType.new(interface_name))
          end

          builder.build_merged_fields(self, type_name, types_by_location)
        end
      end

      def build_union_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Union) do
          graphql_name(type_name)
          description(builder.merge_descriptions(types_by_location, type_name))

          possible_names = types_by_location.values.flat_map { _1.possible_types.map(&:graphql_name) }
          possible_types *possible_names.map { GraphQL::Schema::LateBoundType.new(_1) }
        end
      end

      def build_input_object_type(type_name, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::InputObject) do
          graphql_name(type_name)
          description(builder.merge_descriptions(types_by_location, type_name))

          args_by_name_location = types_by_location.each_with_object({}) do |(location, type_candidate), memo|
            type_candidate.arguments.each do |argument_name, argument|
              memo[argument_name] ||= {}
              memo[argument_name][location] ||= {}
              memo[argument_name][location] = argument
            end
          end

          args_by_name_location.each do |argument_name, arguments_by_location|
            builder.build_merged_arguments(self, type_name, argument_name, arguments_by_location)
          end
        end
      end

      def build_merged_fields(owner, type_name, types_by_location)
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
          field_types = fields_by_location.values.map(&:type)

          schema_field = owner.field(
            field_name,
            description: merge_descriptions(fields_by_location, type_name, field_name: field_name),
            deprecation_reason: merge_deprecations(fields_by_location, type_name, field_name: field_name),
            type: merge_wrapped_types(field_types, type_name, field_name: field_name),
            null: !field_types.all?(&:non_null?),
            camelize: false,
          )

          # "argument_name" => "location" => argument
          args_by_name_location = fields_by_location.each_with_object({}) do |(location, field_candidate), memo|
            field_candidate.arguments.each do |argument_name, argument|
              memo[argument_name] ||= {}
              memo[argument_name][location] ||= {}
              memo[argument_name][location] = argument
            end
          end

          args_by_name_location.each do |argument_name, arguments_by_location|
            build_merged_arguments(schema_field, type_name, argument_name, arguments_by_location, field_name: field_name)
          end
        end
      end

      def build_merged_arguments(owner, type_name, argument_name, arguments_by_location, field_name: nil)
        argument_types = arguments_by_location.values.map(&:type)

        owner.argument(
          argument_name,
          description: merge_descriptions(arguments_by_location, type_name, field_name: field_name, argument_name: argument_name),
          deprecation_reason: merge_deprecations(arguments_by_location, type_name, field_name: field_name, argument_name: argument_name),
          type: merge_wrapped_types(argument_types, type_name, field_name: field_name, argument_name: argument_name),
          required: argument_types.any?(&:non_null?),
          camelize: false,
        )
      end

      def extract_boundaries(type_name, types_by_location)
        types_by_location.each do |location, type_candidate|
          type_candidate.fields.each do |field_name, field_candidate|
            field_candidate.directives.each do |directive|
              next unless directive.graphql_name == "boundary"

              key = directive.arguments.keyword_arguments.fetch(:key)
              key_selections = GraphQL.parse("{ #{key} }").definitions[0].selections

              if key_selections.length != 1
                raise "Boundary key at #{type_name}.#{field_name} must specify exactly one key."
              end

              field_argument = key_selections[0].alias
              field_argument ||= if field_candidate.arguments.size == 1
                field_candidate.arguments.keys.first
              end

              @boundary_map[type_name] ||= []
              @boundary_map[type_name] << {
                "location" => location,
                "selection" => key_selections[0].name,
                "field" => field_candidate.name,
                "arg" => field_argument,
              }
            end
          end
        end
      end

      def merge_wrapped_types(type_candidates, type_name, field_name: nil, argument_name: nil)
        path = [type_name, field_name, argument_name].compact.join(".")
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

      def merge_descriptions(members_by_location, type_name, field_name: nil, argument_name: nil)
        members_by_location.values.map(&:description).find { !_1.nil? }
      end

      def merge_deprecations(members_by_location, type_name, field_name: nil, argument_name: nil)
        members_by_location.values.map(&:deprecation_reason).find { !_1.nil? }
      end
    end
  end
end
