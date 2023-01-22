# frozen_string_literal: true

module GraphQL
  module Stitching
    class Compose

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

          # if is_builtin_scalar?
        end

        # GraphQL::Schema::BUILT_IN_TYPES

        types = type_candidates_map.each_with_object({}) do |(typename, types_by_location), memo|
          candidates = types_by_location.values
          member_class = candidates.first.ancestors.find { _1.name.start_with?('GraphQL::Schema::') }
          unless candidates.any? { _1 <= member_class }
            raise "Cannot merge different member types for #{typename}."
          end

          memo[typename] = case member_class.name
          when "GraphQL::Schema::Scalar"
            build_scalar_type(typename, types_by_location)
          when "GraphQL::Schema::Enum"
            build_enum_type(typename, types_by_location)
          when "GraphQL::Schema::Object"
            build_object_type(typename, types_by_location)
          when "GraphQL::Schema::Interface"
            build_interface_type(typename, types_by_location)
          when "GraphQL::Schema::Union"
            build_union_type(typename, types_by_location)
          when "GraphQL::Schema::InputObject"
            build_input_object_type(typename, types_by_location)
          else
            raise "Unexpected #{member_class} encountered for type #{typename}."
          end
        end


        # schema = Class.new(GraphQL::Schema) do

        # end
        byebug
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
          values = candidates.each_with_object({}) do |candidate, memo|
            candidate.values.each do |value|
              memo[value.to_s] ||= [value]
              memo[value.to_s] << value
            end
          end

          # enum_type_definition.values.each do |enum_value_definition|
          #   value(enum_value_definition.name,
          #     value: enum_value_definition.name,
          #     deprecation_reason: builder.build_deprecation_reason(enum_value_definition.directives),
          #     description: enum_value_definition.description,
          #     directives: builder.prepare_directives(enum_value_definition, type_resolver),
          #     ast_node: enum_value_definition,
          #   )
          # end
        end
      end

      def build_object_type(typename, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Object) do
          graphql_name(typename)
          description(builder.merge_descriptions(types_by_location))

          # object_type_definition.interfaces.each do |interface_name|
          #   interface_defn = type_resolver.call(interface_name)
          #   implements(interface_defn)
          # end

          # builder.build_fields(self, object_type_definition.fields, type_resolver, default_resolve: true)
          builder.build_merged_fields(typename, types_by_location, self)
        end
      end

      def build_interface_type(typename, types_by_location)
        builder = self

        Module.new do
          include GraphQL::Schema::Interface
          graphql_name(typename)
          description(builder.merge_descriptions(types_by_location))
          # interface_type_definition.interfaces.each do |interface_name|
          #   interface_defn = type_resolver.call(interface_name)
          #   implements(interface_defn)
          # end
          builder.build_merged_fields(typename, types_by_location, self)
        end
      end

      def build_merged_fields(typename, types_by_location, owner)
        fields_by_name = types_by_location.each_with_object({}) do |(location, type), memo|
          @field_map[typename] ||= {}
          type.fields.each do |fieldname, field|
            @field_map[typename][field.name] ||= []
            @field_map[typename][field.name] << location

            memo[fieldname] ||= []
            memo[fieldname] << field
          end
        end

        fields_by_name.each do |fieldname, fields|
          named_types = fields.map { Util.get_named_type(_1.type) }

          is_list = fields.map { Util.is_list_type?(_1.type) }
          if is_list.all? { _1 != is_list.first }
            raise "Cannot merge mixed list types at #{typename}.#{fieldname}."
          else
            is_list.first
          end

          is_non_null = fields.map { _1.type.non_null? }.all?
          is_non_null_element = fields.map { Util.is_non_null_list_element?(_1.type) }.all?

          byebug
        end
      end

      def build_union_type(typename, types_by_location)
        builder = self

        Class.new(GraphQL::Schema::Union) do
          graphql_name(typename)
          description(builder.merge_descriptions(types_by_location))
          # possible_types(*union_type_definition.types.map { |type_name| type_resolver.call(type_name) })
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

      # def build_resolve_type(lookup_hash, directives, missing_type_handler)

      # ->(type_name) { types[type_name] ||= Schema::LateBoundType.new(type_name)})

      #   resolve_type_proc = nil
      #   resolve_type_proc = ->(ast_node) {
      #     case ast_node
      #     when GraphQL::Language::Nodes::TypeName
      #       type_name = ast_node.name
      #       if lookup_hash.key?(type_name)
      #         lookup_hash[type_name]
      #       else
      #         missing_type_handler.call(type_name)
      #       end
      #     when GraphQL::Language::Nodes::NonNullType
      #       resolve_type_proc.call(ast_node.of_type).to_non_null_type
      #     when GraphQL::Language::Nodes::ListType
      #       resolve_type_proc.call(ast_node.of_type).to_list_type
      #     when String
      #       directives[ast_node]
      #     else
      #       raise "Unexpected ast_node: #{ast_node.inspect}"
      #     end
      #   }
      #   resolve_type_proc
      # end

      def merge_descriptions(types_by_location)
        # types_by_location.each_with_object({}) { |(l, t), m| m[l] = t.description }
        types_by_location.values.map(&:description).find { !_1.nil? }
      end
    end
  end
end
