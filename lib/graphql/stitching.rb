# frozen_string_literal: true

require "graphql"

module GraphQL
  module Stitching
    EMPTY_OBJECT = {}.freeze

    class StitchingError < StandardError; end

    class << self

      def stitch_directive
        @stitch_directive ||= "stitch"
      end

      attr_writer :stitch_directive

      def stitching_directive_names
        [stitch_directive]
      end

      def schema_from_definition(sdl, stitch_directives:)
        ast = GraphQL.parse(sdl)

        if stitch_directives&.any?
          directive_definition = ast.definitions.find do |d|
            d.is_a?(GraphQL::Language::Nodes::DirectiveDefinition) && d.name == stitch_directive
          end

          if !directive_definition
            directive_sdl = "directive @#{stitch_directive}(key: String!) repeatable on FIELD_DEFINITION"
            directive_definition = GraphQL.parse(directive_sdl).definitions.first
            ast.send(:merge!, { definitions: [directive_definition, *ast.definitions] })
          end
        end

        stitch_directives.each do |config|
          config[:type_name] ||= "Query"

          type_node = ast.definitions.find do |d|
            d.is_a?(GraphQL::Language::Nodes::ObjectTypeDefinition) && d.name == config[:type_name]
          end

          raise StitchingError, "invalid type name `#{config[:type_name]}`." unless type_node

          field_node = type_node.fields.find do |f|
            f.name == config[:field_name]
          end

          raise StitchingError, "invalid field name `#{config[:field_name]}`." unless field_node

          field_node.send(:merge!, {
            directives: [
              *field_node.directives,
              GraphQL::Language::Nodes::Directive.new(
                arguments: [GraphQL::Language::Nodes::Argument.new(name: "key", value: config[:key])],
                name: stitch_directive,
              )
            ]
          })
        end

        GraphQL::Schema::BuildFromDefinition.from_document(GraphQL::Schema, ast, default_resolve: nil)
      end
    end
  end
end

require_relative "stitching/gateway"
require_relative "stitching/supergraph"
require_relative "stitching/composer"
require_relative "stitching/executor"
require_relative "stitching/planner_operation"
require_relative "stitching/planner"
require_relative "stitching/remote_client"
require_relative "stitching/request"
require_relative "stitching/shaper"
require_relative "stitching/util"
require_relative "stitching/version"
