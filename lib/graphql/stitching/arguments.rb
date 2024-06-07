# frozen_string_literal: true

module GraphQL
  module Stitching
    module Arguments
      class Argument
        attr_reader :name
        attr_reader :value
        attr_reader :type_name

        def initialize(name:, value:, list: false, type_name: nil)
          @name = name
          @value = value
          @list = list
          @type_name = type_name
        end

        def list?
          @list
        end

        def ==(other)
          self.class == other.class &&
            @name == other.name &&
            @value == other.value &&
            @type_name == other.type_name &&
            @list == other.list?
        end

        def as_json
          {
            node: "argument",
            name: name,
            type_name: type_name,
            list: list? || nil,
            value: value.as_json,
          }.tap(&:compact!)
        end

        def build(origin_obj)
          val = value.build(origin_obj)
          val = [val] if list?
          val
        end
      end

      class ArgumentValue
        attr_reader :value

        def initialize(value)
          @value = value
        end

        def ==(other)
          self.class == other.class && value == other.value
        end

        def as_json
          raise "unimplemented"
        end

        def build(origin_obj)
          value
        end
      end

      class ObjectValue < ArgumentValue
        def as_json
          {
            node: "object",
            value: @value.map(&:as_json),
          }
        end

        def build(origin_obj)
          value.each_with_object({}) do |arg, memo|
            memo[arg.name] = arg.build(origin_obj)
          end
        end
      end

      class KeyValue < ArgumentValue
        def as_json
          {
            node: "key",
            value: @value,
          }
        end

        def build(origin_obj)
          value.reduce(origin_obj) { |obj, ns| obj[ns] }
        end
      end

      class LiteralValue < ArgumentValue
        def as_json
          {
            node: "literal",
            value: @value,
          }
        end
      end

      class << self
        # "reps: {group: $scope.group, name: $scope.name}, other: 'Sfoo'"
        def parse(template, field_def)
          template = template.gsub("'", %|"|).gsub(/(\$[\w\.]+)/) { %|"#{_1}"| }
          template = template[1..-1] if template.start_with?("(")
          template = template[0..-2] if template.end_with?(")")

          ast = GraphQL.parse("{ f(#{template}) }")
            .definitions.first
            .selections.first
            .arguments

          build_argument_set(ast, field_def.arguments, repeatable_key: field_def.type.list?)
        end

        private

        def build_argument_set(nodes, argument_defs, static_scope: false, repeatable_key: false)
          if argument_defs
            argument_defs.each_value do |argument_def|
              if argument_def.type.non_null? && !nodes.find { _1.name == argument_def.graphql_name }
                raise "Required argument `#{argument_def.graphql_name}` has no input."
              end
            end
          end

          nodes.map do |n|
            argument_def = if argument_defs
              unless d = argument_defs[n.name]
                raise "Input `#{n.name}` is not a valid argument."
              end

              # lock the use of keys in a root argument's subtree
              # when the key is repeatable (list fields) but the argument is not.
              static_scope = true if repeatable_key && !d.type.list?
              d
            end

            build_argument(n, argument_def, static_scope:)
          end
        end

        def build_argument(node, argument_def, static_scope: false)
          value = if node.value.is_a?(GraphQL::Language::Nodes::InputObject)
            object_def = argument_def ? argument_def.type.unwrap : nil
            build_object_value(node.value, object_def, static_scope:)
          elsif node.value.is_a?(String) && node.value.start_with?("$.")
            if static_scope
              raise "Cannot use repeatable key `#{node.value}` in non-list argument `#{argument_def&.graphql_name}`."
            end
            KeyValue.new(node.value.sub(/^\$\./, "").split("."))
          else
            LiteralValue.new(node.value)
          end

          Argument.new(
            name: node.name,
            value: value,
            list: argument_def ? argument_def.type.list? : false,
            type_name: argument_def ? argument_def.type.unwrap.graphql_name : nil,
          )
        end

        def build_object_value(node, object_def, static_scope: false)
          if object_def
            if !object_def.kind.input_object? && !object_def.kind.scalar?
              raise "Objects can only be built into input object and scalar positions."
            elsif object_def.kind.scalar? && GraphQL::Schema::BUILT_IN_TYPES[object_def.graphql_name]
              raise "Objects can only be built into custom scalar types."
            elsif object_def.kind.scalar?
              object_def = nil
            end
          end

          ObjectValue.new(build_argument_set(node.arguments, object_def&.arguments, static_scope:))
        end
      end
    end
  end
end
