# frozen_string_literal: true

module GraphQL
  module Stitching
    class Document
      SUPPORTED_OPERATIONS = ["query", "mutation"].freeze

      attr_reader :ast, :operation_name

      def initialize(string_or_ast, operation_name: nil)
        @ast = if string_or_ast.is_a?(String)
          GraphQL.parse(string_or_ast)
        else
          string_or_ast
        end

        @operation_name = operation_name
      end

      def operation
        @operation ||= begin
          operation_defs = @ast.definitions.select do |d|
            next unless d.is_a?(GraphQL::Language::Nodes::OperationDefinition)
            next unless SUPPORTED_OPERATIONS.include?(d.operation_type)
            @operation_name ? d.name == @operation_name : true
          end

          if operation_defs.length < 1
            raise GraphQL::ExecutionError, "Invalid root operation."
          elsif operation_defs.length > 1
            raise GraphQL::ExecutionError, "An operation name is required when sending multiple operations."
          end

          operation_defs.first
        end
      end

      def variable_definitions
        @variable_definitions ||= operation.variables.each_with_object({}) do |v, memo|
          memo[v.name] = v.type
        end
      end

      def fragment_definitions
        @fragment_definitions ||= @ast.definitions.each_with_object({}) do |d, memo|
          memo[d.name] = d if d.is_a?(GraphQL::Language::Nodes::FragmentDefinition)
        end
      end
    end
  end
end
