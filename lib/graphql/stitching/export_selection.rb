# frozen_string_literal: true

module GraphQL
  module Stitching
    # Builds hidden selection fields added by stitiching code,
    # used to request operational data about resolved objects.
    class ExportSelection
      EXPORT_PREFIX = "_export_"

      class << self
        @typename_node = nil

        def key?(name)
          return false unless name

          name.start_with?(EXPORT_PREFIX)
        end

        def key(name)
          "#{EXPORT_PREFIX}#{name}"
        end

        # The argument assigning Field.alias changed from
        # a generic `alias` hash key to a structured `field_alias` kwarg.
        # See https://github.com/rmosolgo/graphql-ruby/pull/4718
        FIELD_ALIAS_KWARG = !GraphQL::Language::Nodes::Field.new(field_alias: "a").alias.nil?

        def key_node(field_name)
          if FIELD_ALIAS_KWARG
            GraphQL::Language::Nodes::Field.new(field_alias: key(field_name), name: field_name)
          else
            GraphQL::Language::Nodes::Field.new(alias: key(field_name), name: field_name)
          end
        end

        def typename_node
          @typename_node ||= key_node("__typename")
        end
      end
    end
  end
end
