# frozen_string_literal: true

module GraphQL
  module Stitching
    class Request
      SUPPORTED_OPERATIONS = ["query", "mutation"].freeze

      attr_reader :document, :variables, :operation_name, :context

      def initialize(document, operation_name: nil, variables: nil, context: nil)
        @may_contain_runtime_directives = true

        @document = if document.is_a?(String)
          @may_contain_runtime_directives = document.include?("@")
          GraphQL.parse(document)
        else
          document
        end

        @operation_name = operation_name
        @variables = variables || {}
        @context = context || GraphQL::Stitching::EMPTY_OBJECT
      end

      def string
        @string ||= @document.to_query_string
      end

      def digest
        @digest ||= Digest::SHA2.hexdigest(string)
      end

      def operation
        @operation ||= begin
          operation_defs = @document.definitions.select do |d|
            next unless d.is_a?(GraphQL::Language::Nodes::OperationDefinition)
            next unless SUPPORTED_OPERATIONS.include?(d.operation_type)
            @operation_name ? d.name == @operation_name : true
          end

          if operation_defs.length < 1
            raise GraphQL::ExecutionError, "Invalid root operation for given name and operation type."
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
        @fragment_definitions ||= @document.definitions.each_with_object({}) do |d, memo|
          memo[d.name] = d if d.is_a?(GraphQL::Language::Nodes::FragmentDefinition)
        end
      end

      def prepare!
        operation.variables.each do |v|
          @variables[v.name] ||= v.default_value
        end

        if @may_contain_runtime_directives
          @document, modified = SkipInclude.render(@document, @variables)

          if modified
            @string = nil
            @digest = nil
            @operation = nil
            @variable_definitions = nil
            @fragment_definitions = nil
          end
        end

        self
      end
    end
  end
end
