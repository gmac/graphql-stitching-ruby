# frozen_string_literal: true

module GraphQL
  module Stitching
    class PlannerOperation
      LANGUAGE_PRINTER = GraphQL::Language::Printer.new

      attr_reader :order, :location, :parent_type, :if_type, :operation_type, :path
      attr_accessor :after, :selections, :variables, :boundary

      def initialize(
        location:,
        parent_type:,
        order:,
        after: nil,
        operation_type: "query",
        selections: [],
        variables: [],
        path: [],
        if_type: nil,
        boundary: nil
      )
        @location = location
        @parent_type = parent_type
        @order = order
        @after = after
        @operation_type = operation_type
        @selections = selections
        @variables = variables
        @path = path
        @if_type = if_type
        @boundary = boundary
      end

      def selection_set
        op = GraphQL::Language::Nodes::OperationDefinition.new(selections: @selections)
        LANGUAGE_PRINTER.print(op).gsub!(/\s+/, " ").strip!
      end

      def variable_set
        @variables.each_with_object({}) do |(variable_name, value_type), memo|
          memo[variable_name] = LANGUAGE_PRINTER.print(value_type)
        end
      end

      def to_h
        data = {
          "order" => @order,
          "after" => @after,
          "location" => @location,
          "operation_type" => @operation_type,
          "selections" => selection_set,
          "variables" => variable_set,
          "path" => @path,
        }

        data["if_type"] = @if_type if @if_type
        data["boundary"] = @boundary if @boundary
        data
      end
    end
  end
end
