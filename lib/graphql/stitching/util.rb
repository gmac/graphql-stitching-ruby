# frozen_string_literal: true

module GraphQL
  module Stitching
    class Util
      TypeStructure = Struct.new(:list, :null, :name, keyword_init: true) do
        alias_method :list?, :list
        alias_method :null?, :null

        def non_null?
          !null
        end
      end

      class << self
        # specifies if a type is a primitive leaf value
        def is_leaf_type?(type)
          type.kind.scalar? || type.kind.enum?
        end

        # strips non-null wrappers from a type
        def unwrap_non_null(type)
          type = type.of_type while type.non_null?
          type
        end

        # builds a single-dimensional representation of a wrapped type structure
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

        # builds a single-dimensional representation of a wrapped type structure from AST
        def flatten_ast_type_structure(ast, structure: [])
          null = true

          while ast.is_a?(GraphQL::Language::Nodes::NonNullType)
            ast = ast.of_type
            null = false
          end

          if ast.is_a?(GraphQL::Language::Nodes::ListType)
            structure << TypeStructure.new(
              list: true,
              null: null,
              name: nil,
            )

            flatten_ast_type_structure(ast.of_type, structure: structure)
          else
            structure << TypeStructure.new(
              list: false,
              null: null,
              name: ast.name,
            )
          end

          structure
        end

        # expands interfaces and unions to an array of their memberships
        # like `schema.possible_types`, but includes child interfaces
        def expand_abstract_type(schema, parent_type)
          return [] unless parent_type.kind.abstract?
          return parent_type.possible_types if parent_type.kind.union?

          result = []
          schema.types.each_value do |type|
            next unless type <= GraphQL::Schema::Interface && type != parent_type
            next unless type.interfaces.include?(parent_type)
            result << type
            result.push(*expand_abstract_type(schema, type)) if type.kind.interface?
          end
          result.tap(&:uniq!)
        end
      end
    end
  end
end
