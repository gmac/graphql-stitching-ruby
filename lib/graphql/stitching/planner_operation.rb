# frozen_string_literal: true

module GraphQL
  module Stitching
    class PlannerOperation
      LANGUAGE_PRINTER = GraphQL::Language::Printer.new

      attr_reader :key, :location, :parent_type, :type_condition, :operation_type, :insertion_path
      attr_accessor :after_key, :selections, :variables, :boundary

      def initialize(
        key:,
        location:,
        parent_type:,
        operation_type: "query",
        insertion_path: [],
        type_condition: nil,
        after_key: nil,
        selections: [],
        variables: [],
        boundary: nil
      )
        @key = key
        @after_key = after_key
        @location = location
        @parent_type = parent_type
        @operation_type = operation_type
        @insertion_path = insertion_path
        @type_condition = type_condition
        @selections = selections
        @variables = variables
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
        {
          "key" => @key,
          "after_key" => @after_key,
          "location" => @location,
          "operation_type" => @operation_type,
          "insertion_path" => @insertion_path,
          "type_condition" => @type_condition,
          "selections" => selection_set,
          "variables" => variable_set,
          "boundary" => @boundary,
        }
      end
    end
  end
end
