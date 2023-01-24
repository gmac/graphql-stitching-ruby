# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Util
      def self.get_named_type(type)
        while type.respond_to?(:of_type)
          type = type.of_type
        end
        type
      end

      def self.get_list_structure(type)
        structure = []
        previous = nil
        while type.respond_to?(:of_type)
          if type.is_a?(GraphQL::Schema::List)
            structure.push(previous.is_a?(GraphQL::Schema::NonNull) ? :non_null_list : :list)
          end
          if structure.any?
            previous = type
            if !type.of_type.respond_to?(:of_type)
              structure.push(previous.is_a?(GraphQL::Schema::NonNull) ? :non_null_element : :element)
            end
          end
          type = type.of_type
        end
        structure
      end

      def self.get_implementing_types(schema, parent_type)
        result = []
        schema.types.values.each do |type|
          next unless type <= GraphQL::Schema::Interface && type != parent_type
          next unless type.interfaces.include?(parent_type)
          result << type
          result.push(*get_implementing_types(schema, type)) if type.kind.name == "INTERFACE"
        end
        result.uniq
      end

      def self.is_leaf_type?(type)
        type.kind.name == "SCALAR" || type.kind.name == "ENUM"
      end

      def self.is_abstract_type?(type)
        type.kind.name == "INTERFACE" || type.kind.name == "UNION"
      end
    end
  end
end
