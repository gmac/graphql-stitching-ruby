# frozen_string_literal: true

module GraphQL::Stitching
  class Planner
    # A planned step in the sequence of stitching entrypoints together.
    # This is a mutable object that may change throughout the planning process.
    # It ultimately builds an immutable Plan::Op at the end of planning.
    class Step
      GRAPHQL_PRINTER = GraphQL::Language::Printer.new

      attr_reader :index, :location, :parent_type, :operation_type, :path
      attr_accessor :after, :selections, :variables, :resolver

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
        @location = location
        @parent_type = parent_type
        @index = index
        @after = after
        @operation_type = operation_type
        @selections = selections
        @variables = variables
        @path = path
        @resolver = resolver
      end

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
      def type_condition
        @parent_type.graphql_name if @resolver && !parent_type.kind.abstract?
      end

      def rendered_selections
        op = GraphQL::Language::Nodes::OperationDefinition.new(operation_type: "", selections: @selections)
        GRAPHQL_PRINTER.print(op).gsub(/\s+/, " ").strip
      end

      def rendered_variables
        @variables.each_with_object({}) do |(variable_name, value_type), memo|
          memo[variable_name] = GRAPHQL_PRINTER.print(value_type)
        end
      end
    end
  end
end
