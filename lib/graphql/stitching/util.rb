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
        while type.is_a?(GraphQL::Schema::NonNull)
          type = type.of_type
        end
        type
      end

      # gets a named type for a field node, including hidden root introspections
      def self.named_type_for_field_node(schema, parent_type, node)
        if node.name == "__schema" && parent_type == schema.query
          schema.types["__Schema"]
        else
          parent_type.fields[node.name].type.unwrap
        end
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

      # gets a deep structural description of a list value type
      def self.get_list_structure(type)
        structure = []
        previous = nil
        while type.respond_to?(:of_type)
          if type.is_a?(GraphQL::Schema::List)
            structure.push(previous.is_a?(GraphQL::Schema::NonNull) ? "non_null_list" : "list")
          end
          if structure.any?
            previous = type
            if !type.of_type.respond_to?(:of_type)
              structure.push(previous.is_a?(GraphQL::Schema::NonNull) ? "non_null_element" : "element")
            end
          end
          type = type.of_type
        end
        structure
      end
    end
  end
end
