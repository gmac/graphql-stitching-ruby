# frozen_string_literal: true

module GraphQL
  module Stitching
    class Util
      # specifies if a type is a primitive leaf value
      def self.is_leaf_type?(type)
        type.kind.scalar? || type.kind.enum?
      end

      # strips non-null wrappers from a type
      def self.unwrap_non_null(type)
        type = type.of_type while type.non_null?
        type
      end

      # builds a single-dimensional representation of a wrapped type structure
      def self.flatten_type_structure(type)
        structure = []

        while type.list?
          structure << {
            list: true,
            null: !type.non_null?,
            name: nil,
          }

          type = unwrap_non_null(type).of_type
        end

        structure << {
          list: false,
          null: !type.non_null?,
          name: type.unwrap.graphql_name,
        }

        structure
      end

      # gets a named type for a field node, including hidden root introspections
      def self.type_for_field_node(schema, parent_type, node)
        if parent_type == schema.query
          case node.name
          when "__schema"
            return schema.types["__Schema"]
          when "__type"
            return schema.types["__Type"]
          end
        end
        parent_type.fields[node.name].type
      end

      # expands interfaces and unions to an array of their memberships
      # like `schema.possible_types`, but includes child interfaces
      def self.expand_abstract_type(schema, parent_type)
        return [] unless parent_type.kind.abstract?
        return parent_type.possible_types if parent_type.kind.union?

        result = []
        schema.types.values.each do |type|
          next unless type <= GraphQL::Schema::Interface && type != parent_type
          next unless type.interfaces.include?(parent_type)
          result << type
          result.push(*expand_abstract_type(schema, type)) if type.kind.interface?
        end
        result.uniq
      end
    end
  end
end
