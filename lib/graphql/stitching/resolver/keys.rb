# frozen_string_literal: true

module GraphQL::Stitching
  class Resolver
    EXPORT_PREFIX = "_export_"
    TYPE_NAME = "__typename"

    class FieldNode
      # GraphQL Ruby changed the argument assigning Field.alias from
      # a generic `alias` hash key to a structured `field_alias` kwarg
      # in https://github.com/rmosolgo/graphql-ruby/pull/4718.
      # This adapts to the library implementation present.
      GRAPHQL_RUBY_FIELD_ALIAS_KWARG = !GraphQL::Language::Nodes::Field.new(field_alias: "a").alias.nil?

      class << self
        def build(field_name:, field_alias: nil, selections: GraphQL::Stitching::EMPTY_ARRAY)
          if GRAPHQL_RUBY_FIELD_ALIAS_KWARG
            GraphQL::Language::Nodes::Field.new(
              field_alias: field_alias,
              name: field_name,
              selections: selections,
            )
          else
            GraphQL::Language::Nodes::Field.new(
              alias: field_alias,
              name: field_name,
              selections: selections,
            )
          end
        end
      end
    end

    class KeyFieldSet < Array
      def initialize(fields)
        super(fields.sort_by(&:name))
        @to_definition = nil
        @export_nodes = nil
      end

      def ==(other)
        to_definition == other.to_definition
      end

      def primitive_name
        length == 1 ? first.name : nil
      end

      def to_definition
        @to_definition ||= map(&:to_definition).join(" ").freeze
      end

      alias_method :to_s, :to_definition

      def export_nodes
        @export_nodes ||= map(&:export_node)
      end
    end

    EMPTY_FIELD_SET = KeyFieldSet.new(GraphQL::Stitching::EMPTY_ARRAY)
    TYPENAME_EXPORT_NODE = FieldNode.build(
      field_alias: "#{EXPORT_PREFIX}#{TYPE_NAME}",
      field_name: TYPE_NAME,
    )

    class Key < KeyFieldSet
      attr_reader :locations

      def initialize(fields, locations: GraphQL::Stitching::EMPTY_ARRAY)
        super(fields)
        @locations = locations
        to_definition
        export_nodes
        freeze
      end

      def export_nodes
        @export_nodes ||= begin
          nodes = map(&:export_node)
          nodes << TYPENAME_EXPORT_NODE
          nodes
        end
      end
    end

    class KeyField
      # name of the key, may be a field alias
      attr_reader :name

      # inner key selections
      attr_reader :inner

      # optional information about location and typing, used during composition
      attr_accessor :type_name
      attr_accessor :list
      alias_method :list?, :list

      def initialize(name, root: false, inner: EMPTY_FIELD_SET)
        @name = name
        @inner = inner
        @root = root
      end

      def to_definition
        @inner.empty? ? @name : "#{@name} { #{@inner.to_definition} }"
      end

      def export_node
        FieldNode.build(
          field_alias: @root ? "#{EXPORT_PREFIX}#{@name}" : nil,
          field_name: @name,
          selections: @inner.export_nodes,
        )
      end
    end

    module KeysParser
      def export_key(name)
        "#{EXPORT_PREFIX}#{name}"
      end

      def export_key?(name)
        return false unless name

        name.start_with?(EXPORT_PREFIX)
      end

      def parse_key(template, locations = GraphQL::Stitching::EMPTY_ARRAY)
        Key.new(parse_field_set(template), locations: locations)
      end

      def parse_key_with_types(template, subgraph_types_by_location)
        field_set = parse_field_set(template)
        locations = subgraph_types_by_location.filter_map do |location, subgraph_type|
          location if field_set_matches_type?(field_set, subgraph_type)
        end

        if locations.none?
          message = "Key `#{field_set.to_definition}` does not exist in any location."
          message += " Composite key selections may not be distributed." if field_set.length > 1
          raise CompositionError, message
        end

        assign_field_set_info!(field_set, subgraph_types_by_location[locations.first])
        Key.new(field_set, locations: locations)
      end

      private

      def parse_field_set(template)
        template = template.strip
        template = template[1..-2] if template.start_with?("{") && template.end_with?("}")

        ast = GraphQL.parse("{ #{template} }").definitions.first.selections
        build_field_set(ast, root: true)
      end

      def build_field_set(selections, root: false)
        return EMPTY_FIELD_SET if selections.empty?

        fields = selections.map do |node|
          raise CompositionError, "Key selections must be fields." unless node.is_a?(GraphQL::Language::Nodes::Field)
          raise CompositionError, "Key fields may not specify aliases." unless node.alias.nil?

          KeyField.new(node.name, inner: build_field_set(node.selections), root: root)
        end

        KeyFieldSet.new(fields)
      end

      def field_set_matches_type?(field_set, subgraph_type)
        subgraph_type = subgraph_type.unwrap
        field_set.all? do |field|
          # fixme: union doesn't have fields, but may support these selections...
          next true if subgraph_type.kind.union?
          field_matches_type?(field, subgraph_type.get_field(field.name)&.type&.unwrap)
        end
      end

      def field_matches_type?(field, subgraph_type)
        return false if subgraph_type.nil?

        if field.inner.empty? && subgraph_type.kind.composite?
          raise CompositionError, "Composite key fields must contain nested selections."
        end

        field.inner.empty? || field_set_matches_type?(field.inner, subgraph_type)
      end

      def assign_field_set_info!(field_set, subgraph_type)
        subgraph_type = subgraph_type.unwrap
        field_set.each do |field|
          # fixme: union doesn't have fields, but may support these selections...
          next if subgraph_type.kind.union?
          assign_field_info!(field, subgraph_type.get_field(field.name).type)
        end
      end

      def assign_field_info!(field, subgraph_type)
        field.list = subgraph_type.list?
        field.type_name = subgraph_type.unwrap.graphql_name
        assign_field_set_info!(field.inner, subgraph_type)
      end
    end
  end
end
