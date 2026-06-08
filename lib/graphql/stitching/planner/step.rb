# frozen_string_literal: true
# typed: true

module GraphQL::Stitching
  class Planner
    # A planned step in the sequence of stitching entrypoints together.
    # This is a mutable object that may change throughout the planning process.
    # It ultimately builds an immutable Plan::Op at the end of planning.
    class Step
      GRAPHQL_PRINTER = GraphQL::Language::Printer.new

      #: Integer
      attr_reader :index

      #: String
      attr_reader :location

      #: CompositeType
      attr_reader :parent_type

      #: String
      attr_reader :operation_type

      #: Array[String]
      attr_reader :path

      #: Integer?
      attr_accessor :after

      #: Array[SelectionNode]
      attr_accessor :selections

      #: Variables
      attr_accessor :variables

      #: TypeResolver?
      attr_accessor :resolver

      #: (
      #|   location: String,
      #|   parent_type: CompositeType,
      #|   index: Integer,
      #|   ?after: Integer?,
      #|   ?operation_type: String,
      #|   ?selections: Array[SelectionNode],
      #|   ?variables: Variables,
      #|   ?path: Array[String],
      #|   ?resolver: TypeResolver?
      #| ) -> void
      def initialize(
        location:,
        parent_type:,
        index:,
        after: nil,
        operation_type: QUERY_OP,
        selections: [],
        variables: {},
        path: [],
        resolver: nil
      )
        @location = location #: Location
        @parent_type = parent_type #: CompositeType
        @index = index #: Integer
        @after = after #: Integer?
        @operation_type = operation_type #: String
        @selections = selections #: Array[SelectionNode]
        @variables = variables #: Variables
        @path = path #: Array[String]
        @resolver = resolver #: TypeResolver?
      end

      #: -> Plan::Op
      def to_plan_op
        GraphQL::Stitching::Plan::Op.new(
          step: @index,
          after: @after,
          location: @location,
          operation_type: @operation_type,
          selections: rendered_selections,
          variables: rendered_variables,
          path: @path,
          if_type: type_condition,
          resolver: @resolver&.version,
        )
      end

      private

      # Concrete types going to a resolver report themselves as a type condition.
      # This is used by the executor to evalute which planned fragment selections
      # actually apply to the resolved object types.
      #: -> String?
      def type_condition
        @parent_type.graphql_name if @resolver && !parent_type.kind.abstract?
      end

      #: -> String
      def rendered_selections
        op = GraphQL::Language::Nodes::OperationDefinition.new(operation_type: "", selections: @selections)
        GRAPHQL_PRINTER.print(op).gsub!(/\s+/, " ").strip!
      end

      #: -> RenderedVariables
      def rendered_variables
        @variables.each_with_object({}) do |(variable_name, value_type), memo|
          memo[variable_name] = GRAPHQL_PRINTER.print(value_type)
        end
      end
    end
  end
end
