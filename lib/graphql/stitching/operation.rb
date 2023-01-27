# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Operation
      attr_reader :key, :location, :operation_type, :insertion_path
      attr_accessor :after_key, :selections, :boundary

      def initialize(
        key:,
        location:,
        after_key: nil,
        operation_type: "query",
        insertion_path: [],
        selections: [],
        variables: [],
        boundary: nil
      )
        @key = key
        @after_key = after_key
        @location = location
        @operation_type = operation_type
        @insertion_path = insertion_path
        @selections = selections
        @variables = variables
        @boundary = boundary
      end

      def selection_set
        op = GraphQL::Language::Nodes::OperationDefinition.new(selections: @selections)
        GraphQL::Language::Printer.new.print(op).gsub(/\s+/, " ")
      end

      def variable_set
        @variables.each_with_object({}) do |(variable_name, value_type), memo|
          memo[variable_name] = GraphQL::Language::Printer.new.print(value_type)
        end
      end

      def as_json
        {
          key: @key,
          after_key: @after_key,
          location: @location,
          operation_type: @operation_type,
          insertion_path: @insertion_path,
          selections: selection_set,
          variables: variable_set,
          boundary: @boundary,
        }
      end
    end
  end
end
