# frozen_string_literal: true

module GraphQL
  module Stitching
    # Builds hidden selection fields added by stitiching code,
    # used to request operational data about resolved objects.
    class SelectionHint
      HINT_PREFIX = "_STITCH_"

      class << self
        def key?(name)
          return false unless name

          name.start_with?(HINT_PREFIX)
        end

        def key(name)
          "#{HINT_PREFIX}#{name}"
        end

        def key_node(field_name)
          GraphQL::Language::Nodes::Field.new(alias: key(field_name), name: field_name)
        end

        def typename_node
          @typename_node ||= key_node("__typename")
        end
      end
    end
  end
end
