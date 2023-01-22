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

      def self.is_leaf_type?(type)
        LEAF_TYPES.any? { _1 <= type }
      end

      def self.is_composite_type?(type)
        COMPOSITE_TYPES.any? { _1 <= type }
      end
    end
  end
end
