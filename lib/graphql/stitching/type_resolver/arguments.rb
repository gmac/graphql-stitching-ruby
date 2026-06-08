# frozen_string_literal: true
# typed: true

module GraphQL::Stitching
  class TypeResolver
    class Argument
      #: String
      attr_reader :name

      #: ArgumentValue
      attr_reader :value

      #: TypeName?
      attr_reader :type_name

      #: (name: String, value: ArgumentValue, ?list: bool, ?type_name: TypeName?) -> void
      def initialize(name:, value:, list: false, type_name: nil)
        @name = name
        @value = value
        @list = list #: bool
        @type_name = type_name
      end

      #: -> bool
      def list?
        @list
      end

      #: -> bool
      def key?
        value.key?
      end

      #: (Key key) -> bool
      def verify_key(key)
        if key?
          value.verify_key(self, key)
          true
        else
          false
        end
      end

      #: (untyped other) -> bool
      def ==(other)
        self.class == other.class &&
          @name == other.name &&
          @value == other.value &&
          @type_name == other.type_name &&
          @list == other.list?
      end

      #: (Data origin_obj) -> untyped
      def build(origin_obj)
        value.build(origin_obj)
      end

      #: -> String
      def print
        "#{name}: #{value.print}"
      end

      #: -> String
      def to_definition
        print.gsub(%|"|, "'")
      end

      alias_method :to_s, :to_definition

      #: -> String
      def to_type_definition
        "#{name}: #{to_type_signature}"
      end

      #: -> String
      def to_type_signature
        # need to derive nullability...
        list? ? "[#{@type_name}!]!" : "#{@type_name}!"
      end
    end

    class ArgumentValue
      #: untyped
      attr_reader :value

      #: (untyped value) -> void
      def initialize(value)
        @value = value
      end

      #: -> bool
      def key?
        false
      end

      #: (Argument arg, Key key) -> void
      def verify_key(arg, key)
        nil
      end

      #: (untyped other) -> bool
      def ==(other)
        self.class == other.class && value == other.value
      end

      #: (Data origin_obj) -> untyped
      def build(origin_obj)
        value
      end

      #: -> String
      def print
        value
      end
    end

    class ObjectArgumentValue < ArgumentValue
      #: -> bool
      def key?
        value.any?(&:key?)
      end

      #: (Argument arg, Key key) -> void
      def verify_key(arg, key)
        value.each { _1.verify_key(key) }
      end

      #: (Data origin_obj) -> Variables
      def build(origin_obj)
        value.each_with_object({}) do |arg, memo|
          memo[arg.name] = arg.build(origin_obj)
        end
      end

      #: -> String
      def print
        "{#{value.map(&:print).join(", ")}}"
      end
    end

    class KeyArgumentValue < ArgumentValue
      #: (String | Array[String] value) -> void
      def initialize(value)
        super(Array(value))
      end

      #: -> bool
      def key?
        true
      end

      #: (Argument arg, Key key) -> void
      def verify_key(arg, key)
        key_field = value.reduce(TypeResolver::KeyField.new("", inner: key)) do |field, ns|
          if ns == TYPENAME
            TypeResolver::KeyField.new(TYPENAME)
          elsif field
            field.inner.find { _1.name == ns }
          end
        end

        # still not capturing enough type information to accurately compare key/arg types...
        # best we can do for now is to verify the argument insertion matches a key path.
        if key_field.nil?
          raise CompositionError, "Argument `#{arg.name}: #{print}` cannot insert key `#{key.to_definition}`."
        end
      end

      #: (Data origin_obj) -> untyped
      def build(origin_obj)
        value.each_with_index.reduce(origin_obj) do |obj, (ns, idx)|
          obj[idx.zero? ? TypeResolver.export_key(ns) : ns]
        end
      end

      #: -> String
      def print
        "$.#{value.join(".")}"
      end
    end

    class EnumArgumentValue < ArgumentValue
    end

    class LiteralArgumentValue < ArgumentValue
      #: -> String
      def print
        JSON.generate(value)
      end
    end

    module ArgumentsParser
      #: (String template, GraphQL::Schema::Field field_def) -> Array[Argument]
      def parse_arguments_with_field(template, field_def)
        ast = parse_arg_defs(template)
        args = build_argument_set(ast, field_def.arguments)
        args.each do |arg|
          next unless arg.key?

          if field_def.type.list? && !arg.list?
            Kernel.raise CompositionError, "Cannot use repeatable key for `#{field_def.owner.graphql_name}.#{field_def.graphql_name}` " \
              "in non-list argument `#{arg.name}`."
          elsif !field_def.type.list? && arg.list?
            Kernel.raise CompositionError, "Cannot use non-repeatable key for `#{field_def.owner.graphql_name}.#{field_def.graphql_name}` " \
              "in list argument `#{arg.name}`."
          end
        end

        args
      end

      #: (String template, String type_defs) -> Array[Argument]
      def parse_arguments_with_type_defs(template, type_defs)
        type_map = parse_type_defs(type_defs)
        parse_arg_defs(template).map { build_argument(_1, type_struct: type_map[_1.name]) }
      end

      private

      #: (String template) -> Array[GraphQL::Language::Nodes::Argument]
      def parse_arg_defs(template)
        template = template
          .gsub("'", %|"|) # 'sfoo' -> "sfoo"
          .gsub(/(\$[\w\.]+)/) { %|"#{_1}"| } # $.key -> "$.key"
          .tap(&:strip!)

        template = template[1..-2] if template.start_with?("(") && template.end_with?(")")

        GraphQL.parse("{ f(#{template}) }")
          .definitions.first
          .selections.first
          .arguments
      end

      #: (String template) -> ResolverArgumentTypeMap
      def parse_type_defs(template)
        GraphQL.parse("type T { #{template} }")
          .definitions.first
          .fields.each_with_object({}) do |node, memo|
            memo[node.name] = GraphQL::Stitching::Util.flatten_ast_type_structure(node.type)
          end
      end

      #: (Array[GraphQL::Language::Nodes::Argument] nodes, untyped argument_defs) -> Array[Argument]
      def build_argument_set(nodes, argument_defs)
        if argument_defs
          argument_defs.each_value do |argument_def|
            if argument_def.type.non_null? && !nodes.find { _1.name == argument_def.graphql_name }
              Kernel.raise CompositionError, "Required argument `#{argument_def.graphql_name}` has no input."
            end
          end
        end

        nodes.map do |node|
          argument_def = if argument_defs
            arg = argument_defs[node.name]
            Kernel.raise CompositionError, "Input `#{node.name}` is not a valid argument." unless arg
            arg
          end

          build_argument(node, argument_def: argument_def)
        end
      end

      #: (GraphQL::Language::Nodes::Argument node, ?argument_def: GraphQL::Schema::Argument?, ?type_struct: Array[Util::TypeStructure]?) -> Argument
      def build_argument(node, argument_def: nil, type_struct: nil)
        value = if node.value.is_a?(GraphQL::Language::Nodes::InputObject)
          build_object_value(node.value, argument_def ? argument_def.type.unwrap : nil)
        elsif node.value.is_a?(GraphQL::Language::Nodes::Enum)
          EnumArgumentValue.new(node.value.name)
        elsif node.value.is_a?(String) && node.value.start_with?("$.")
          KeyArgumentValue.new(node.value.sub(/^\$\./, "").split("."))
        else
          LiteralArgumentValue.new(node.value)
        end

        Argument.new(
          name: node.name,
          value: value,
          # doesn't support nested lists...?
          list: argument_def ? argument_def.type.list? : (type_struct&.first&.list? || false),
          type_name: argument_def ? argument_def.type.unwrap.graphql_name : type_struct&.last&.name,
        )
      end

      #: (GraphQL::Language::Nodes::InputObject node, untyped object_def) -> ObjectArgumentValue
      def build_object_value(node, object_def)
        if object_def
          if !object_def.kind.input_object? && !object_def.kind.scalar?
            Kernel.raise CompositionError, "Objects can only be built into input object and scalar positions."
          elsif object_def.kind.scalar? && GraphQL::Schema::BUILT_IN_TYPES[object_def.graphql_name]
            Kernel.raise CompositionError, "Objects can only be built into custom scalar types."
          elsif object_def.kind.scalar?
            object_def = nil
          end
        end

        ObjectArgumentValue.new(build_argument_set(node.arguments, object_def&.arguments))
      end
    end
  end
end
