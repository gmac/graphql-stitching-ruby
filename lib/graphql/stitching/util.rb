# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Util
      WRAPPER_TYPES = [
        GraphQL::Schema::NonNull,
        GraphQL::Schema::List,
      ].freeze

      LEAF_TYPES = [
        GraphQL::Schema::Scalar,
        GraphQL::Schema::Enum,
      ].freeze

      COMPOSITE_TYPES = [
        GraphQL::Schema::Object,
        GraphQL::Schema::Interface,
      ].freeze

      def self.get_named_type(type)
        while type.respond_to?(:of_type)
          type = type.of_type
        end
        type
      end

      def self.get_list_structure(type)
        structure = []
        while type.respond_to?(:of_type)
          if type.is_a?(GraphQL::Schema::List)
            structure << GraphQL::Schema::List
          elsif structure.any? && type.is_a?(GraphQL::Schema::NonNull)
            structure << GraphQL::Schema::NonNull
          end
          type = type.of_type
        end
        structure
      end

      def self.is_leaf_type?(type)
        LEAF_TYPES.any? { _1 <= type }
      end

      def self.is_composite_type?(type)
        COMPOSITE_TYPES.any? { _1 <= type }
      end
    end
  end
end
