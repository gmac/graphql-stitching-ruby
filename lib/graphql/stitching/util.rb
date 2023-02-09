# frozen_string_literal: true

module GraphQL
  module Stitching
    class Util

      # gets the named type at the bottom of a non-null/list wrapper chain
      def self.get_named_type(type)
        while type.respond_to?(:of_type)
          type = type.of_type
        end
        type
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

      # Gets all objects and interfaces that implement a given interface
      def self.get_possible_types(schema, parent_type)
        return [parent_type] unless parent_type.kind.abstract?
        return parent_type.possible_types if parent_type.kind.union?

        result = []
        schema.types.values.each do |type|
          next unless type <= GraphQL::Schema::Interface && type != parent_type
          next unless type.interfaces.include?(parent_type)
          result << type
          result.push(*get_possible_types(schema, type)) if type.kind.interface?
        end
        result.uniq
      end

      # Specifies if a type is a leaf node (no children)
      def self.is_leaf_type?(type)
        type.kind.scalar? || type.kind.enum?
      end

      def self.get_named_type_for_field_node(schema, parent_type, node)
        if node.name == "__schema" && parent_type == schema.query
          schema.types["__Schema"] # type mapped to phantom introspection field
        else
          Util.get_named_type(parent_type.fields[node.name].type)
        end
      end
    end
  end
end
