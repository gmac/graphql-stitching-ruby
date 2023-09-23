# frozen_string_literal: true

module GraphQL
  module Stitching
    class PlannerStep
      GRAPHQL_PRINTER = GraphQL::Language::Printer.new

      attr_reader :index, :location, :parent_type, :if_type, :operation_type, :path
      attr_accessor :after, :defer_label, :selections, :variables, :boundary

      def initialize(
        location:,
        parent_type:,
        index:,
        after: nil,
        defer_label: nil,
        operation_type: "query",
        selections: [],
        variables: {},
        path: [],
        if_type: nil,
        boundary: nil
      )
        @location = location
        @parent_type = parent_type
        @index = index
        @after = after
        @defer_label = defer_label
        @operation_type = operation_type
        @selections = selections
        @variables = variables
        @path = path
        @if_type = if_type
        @boundary = boundary
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
          if_type: @if_type,
          boundary: @boundary,
          defer_label: @defer_label,
        )
      end

      private

      def rendered_selections
        op = GraphQL::Language::Nodes::OperationDefinition.new(selections: @selections)
        GRAPHQL_PRINTER.print(op).gsub!(/\s+/, " ").strip!
      end

      def rendered_variables
        @variables.each_with_object({}) do |(variable_name, value_type), memo|
          memo[variable_name] = GRAPHQL_PRINTER.print(value_type)
        end
      end
    end
  end
end
