# frozen_string_literal: true

module GraphQL
  module Stitching
    module Arguments
      class Argument
        attr_reader :name
        attr_reader :value
        attr_reader :type_name

        def initialize(name:, value:, type_name: nil, list: false, key: false)
          @name = name
          @value = value
          @type_name = type_name
          @list = list
          @key = key
        end

        def list?
          @list
        end

        def key?
          @key
        end
      end

      class InputObject
        attr_reader :arguments

        def initialize(arguments)
          @arguments = arguments
        end
      end

      class << self
        # "reps: {group: $scope.group, name: $scope.name}, other: 'Sfoo'"
        def parse(definitions_by_name, template)
          template = template.gsub("'", %|"|).gsub(/(\$[\w\.]+)/) { %|"#{_1}"| }

          ast = GraphQL.parse("{ f(#{template}) }")
            .definitions.first
            .selections.first
            .arguments

          ast.map do |node|
            build_argument(node, definitions_by_name[node.name])
          end
        end

        def build_argument(node, definition)
          case node
          when GraphQL::Language::Nodes::Argument
            key = false
            value = if node.value.is_a?(GraphQL::Language::Nodes::AbstractNode)
              build_argument(node.value, definition.type.unwrap)
            elsif node.value.is_a?(String) && node.value.start_with?("$.")
              key = true
              node.value.sub(/^\$\./, "").split(".")
            else
              node.value
            end

            Argument.new(
              name: node.name,
              value: value,
              list: definition.type.list?,
              type_name: definition.type.unwrap.graphql_name,
              key: key
            )
          when GraphQL::Language::Nodes::InputObject
            args = node.arguments.map { |c| build_argument(c, definition.arguments[c.name]) }
            InputObject.new(args)
          end
        end
      end
    end
  end
end
