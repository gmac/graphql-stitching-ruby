# frozen_string_literal: true

module GraphQL
  module Stitching
    module Arguments
      class Argument
        attr_reader :name
        attr_reader :value
        attr_reader :type_name

        def initialize(name:, value:, list: false, key_insert: false, type_name: nil)
          @name = name
          @value = value
          @list = list
          @key_insert = key_insert
          @type_name = type_name
        end

        def list?
          @list
        end

        def key_insert?
          @key_insert
        end

        def as_json
          {
            type: "argument",
            name: name,
            type_name: type_name,
            list: list? || nil,
            key_insert: key_insert? || nil,
            value: value.as_json,
          }.tap(&:compact!)
        end
      end

      class BaseValue
        attr_reader :value

        def initialize(value)
          @value = value
        end

        def as_json
          raise "unimplemented"
        end
      end

      class ObjectValue < BaseValue
        def as_json
          {
            type: "object",
            value: @value.map(&:as_json),
          }
        end
      end

      class KeyValue < BaseValue
        def as_json
          {
            type: "key",
            value: @value,
          }
        end
      end

      class LiteralValue < BaseValue
        def as_json
          {
            type: "literal",
            value: @value,
          }
        end
      end


      class << self
        # "reps: {group: $scope.group, name: $scope.name}, other: 'Sfoo'"
        def parse(argument_defs_by_name, template)
          template = template.gsub("'", %|"|).gsub(/(\$[\w\.]+)/) { %|"#{_1}"| }

          ast = GraphQL.parse("{ f(#{template}) }")
            .definitions.first
            .selections.first
            .arguments

          args = ast.map do |node|
            unless argument_def = argument_defs_by_name[node.name]
              raise "Input `#{node.name}` is not a valid field argument."
            end
            build_argument(node, argument_def)
          end

          ObjectValue.new(args)
        end

        private

        def build_argument(node, argument_def)
          value = if node.value.is_a?(GraphQL::Language::Nodes::InputObject)
            build_object_value(node.value, argument_def ? argument_def.type.unwrap : nil)
          elsif node.value.is_a?(String) && node.value.start_with?("$.")
            KeyValue.new(node.value.sub(/^\$\./, "").split("."))
          else
            LiteralValue.new(node.value)
          end

          Argument.new(
            name: node.name,
            value: value,
            list: argument_def ? argument_def.type.list? : nil,
            type_name: argument_def ? argument_def.type.unwrap.graphql_name : nil,
          )
        end

        def build_object_value(node, object_def)
          if object_def
            if !object_def.kind.input_object? && !object_def.kind.scalar?
              raise "Objects can only be built into input object and scalar positions"
            elsif object_def.kind.scalar? && GraphQL::Schema::BUILT_IN_TYPES[object_def.graphql_name]
              raise "Objects can only be built into custom scalar types"
            elsif object_def.kind.scalar?
              object_def = nil
            end
          end

          args = node.arguments.map do |n|
            argument_def = if object_def
              unless d = object_def.arguments[n.name]
                raise "Input `#{n.name}` is not a valid argument " \
                  "on input object `#{object_def.graphql_name}`."
              end
              d
            end

            build_argument(n, argument_def)
          end

          ObjectValue.new(args)
        end
      end
    end
  end
end
