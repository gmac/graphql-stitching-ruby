# frozen_string_literal: true
# typed: true

module GraphQL
  module Stitching
    class Util
      class TypeStructure
        #: TypeName?
        attr_reader :name

        #: (list: bool, null: bool, name: TypeName?) -> void
        def initialize(list:, null:, name:)
          @list = list #: bool
          @null = null #: bool
          @name = name
        end

        #: -> bool
        def list?
          @list
        end

        #: -> bool
        def null?
          @null
        end

        #: -> bool
        def non_null?
          !@null
        end

        #: (untyped other) -> bool
        def ==(other)
          @list == other.list? && @null == other.null? && @name == other.name
        end
      end

      class << self
        #: (untyped type) -> bool
        def is_leaf_type?(type)
          type.kind.scalar? || type.kind.enum?
        end

        #: (untyped type) -> untyped
        def unwrap_non_null(type)
          type = type.of_type while type.non_null?
          type
        end

        #: (untyped type) -> Array[TypeStructure]
        def flatten_type_structure(type)
          structure = []

          while type.list?
            structure << TypeStructure.new(
              list: true,
              null: !type.non_null?,
              name: nil,
            )

            type = unwrap_non_null(type).of_type
          end

          structure << TypeStructure.new(
            list: false,
            null: !type.non_null?,
            name: type.unwrap.graphql_name,
          )

          structure
        end

        #: (
        #|   GraphQL::Language::Nodes::WrapperType | GraphQL::Language::Nodes::TypeName ast,
        #|   ?structure: Array[TypeStructure]
        #| ) -> Array[TypeStructure]
        def flatten_ast_type_structure(ast, structure: [])
          nullable = true #: bool
          current_ast = ast #: untyped

          while current_ast.is_a?(GraphQL::Language::Nodes::NonNullType)
            current_ast = current_ast.of_type
            nullable = false
          end

          if current_ast.is_a?(GraphQL::Language::Nodes::ListType)
            structure << TypeStructure.new(
              list: true,
              null: nullable,
              name: nil,
            )

            flatten_ast_type_structure(current_ast.of_type, structure: structure)
          else
            structure << TypeStructure.new(
              list: false,
              null: nullable,
              name: current_ast.name,
            )
          end

          structure
        end

      end
    end
  end
end
