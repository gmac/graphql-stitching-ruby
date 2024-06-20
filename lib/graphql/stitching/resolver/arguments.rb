# frozen_string_literal: true

module GraphQL::Stitching
  class Resolver
    # Defines a single resolver argument structure
    # @api private
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

      def key?
        value.key?
      end

      def ==(other)
        self.class == other.class &&
          @name == other.name &&
          @value == other.value &&
          @type_name == other.type_name &&
          @list == other.list?
      end

      def build(origin_obj)
        value.build(origin_obj)
      end

      def print
        "#{name}: #{value.print}"
      end

      def to_definition
        print.gsub(%|"|, "'")
      end

      def to_type_definition
        "#{name}: #{to_type_signature}"
      end

      def to_type_signature
        # need to derive nullability...
        list? ? "[#{@type_name}!]!" : "#{@type_name}!"
      end
    end

    # An abstract argument input value
    # @api private
    class ArgumentValue
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def key?
        false
      end

      def ==(other)
        self.class == other.class && value == other.value
      end

      def build(origin_obj)
        value
      end

      def print
        value
      end
    end

    # An object input value
    # @api private
    class ObjectValue < ArgumentValue
      def key?
        value.any?(&:key?)
      end

      def build(origin_obj)
        value.each_with_object({}) do |arg, memo|
          memo[arg.name] = arg.build(origin_obj)
        end
      end

      def print
        "{#{value.map(&:print).join(", ")}}"
      end
    end

    # A key input value
    # @api private
    class KeyValue < ArgumentValue
      def initialize(value)
        super(Array(value))
      end

      def key?
        true
      end

      def build(origin_obj)
        value.reduce(origin_obj) { |obj, ns| obj[ExportSelection.key(ns)] }
      end

      def print
        "$.#{value.join(".")}"
      end
    end

    # A typed enum input value
    # @api private
    class EnumValue < ArgumentValue
    end

    # A primitive input value literal
    # @api private
    class LiteralValue < ArgumentValue
      def print
        JSON.generate(value)
      end
    end

    # Parser for building argument templates into resolver structures
    # @api private
    module ArgumentsParser
      # Parses an argument template string into resolver arguments via schema casting.
      # @param template [String] the template string to parse.
      # @param field_def [GraphQL::Schema::FieldDefinition] a field definition providing arguments schema.
      # @return [[GraphQL::Stitching::Resolver::Argument]] an array of resolver arguments.
      def parse_arguments(template, field_def)
        ast = parse_arg_defs(template)
        build_argument_set(ast, field_def.arguments, repeatable_key: field_def.type.list?)
      end

      # Parses an argument template string into resolver arguments via SDL casting.
      # @param template [String] the template string to parse.
      # @param type_defs [String] the type definition string declaring argument types.
      # @return [[GraphQL::Stitching::Resolver::Argument]] an array of resolver arguments.
      def parse_arguments_with_type_defs(template, type_defs)
        type_map = parse_type_defs(type_defs)
        parse_arg_defs(template).map { build_argument(_1, nil, type_struct: type_map[_1.name]) }
      end

      private

      def parse_arg_defs(template)
        template = template.gsub("'", %|"|).gsub(/(\$[\w\.]+)/) { %|"#{_1}"| }
        if template.start_with?("(")
          template = template[1..-1]
          template = template[0..-2] if template.end_with?(")")
        end

        GraphQL.parse("{ f(#{template}) }")
          .definitions.first
          .selections.first
          .arguments
      end

      def parse_type_defs(template)
        GraphQL.parse("type T { #{template} }")
          .definitions.first
          .fields.each_with_object({}) do |node, memo|
            memo[node.name] = GraphQL::Stitching::Util.flatten_ast_type_structure(node.type)
          end
      end

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

          build_argument(n, argument_def, static_scope: static_scope)
        end
      end

      def build_argument(node, argument_def, static_scope: false, type_struct: nil)
        value = if node.value.is_a?(GraphQL::Language::Nodes::InputObject)
          object_def = argument_def ? argument_def.type.unwrap : nil
          build_object_value(node.value, object_def, static_scope: static_scope)
        elsif node.value.is_a?(GraphQL::Language::Nodes::Enum)
          EnumValue.new(node.value.name)
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
          # doesn't support nested lists...?
          list: argument_def ? argument_def.type.list? : (type_struct&.first&.list? || false),
          type_name: argument_def ? argument_def.type.unwrap.graphql_name : type_struct&.last&.name,
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

        ObjectValue.new(build_argument_set(node.arguments, object_def&.arguments, static_scope: static_scope))
      end
    end
  end
end
