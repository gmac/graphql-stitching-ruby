# frozen_string_literal: true

module GraphQL
  module Stitching
    class SelectionHint
      HINT_PREFIX = "_STITCH_"
      TYPENAME_NODE = GraphQL::Language::Nodes::Field.new(alias: "#{HINT_PREFIX}typename", name: "__typename")

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

        def typename_key
          TYPENAME_NODE.alias
        end

        def typename_node
          TYPENAME_NODE
        end
      end
    end
  end
end
