# frozen_string_literal: true

module GraphQL
  module Stitching
    class Request
      SUPPORTED_OPERATIONS = ["query", "mutation"].freeze
      SKIP_INCLUDE_DIRECTIVE = /@(?:skip|include)/

      attr_reader :supergraph, :document, :variables, :operation_name, :context

      def initialize(supergraph, document, operation_name: nil, variables: nil, context: nil)
        @supergraph = supergraph
        @string = nil
        @digest = nil
        @normalized_string = nil
        @normalized_digest = nil
        @operation = nil
        @operation_directives = nil
        @variable_definitions = nil
        @fragment_definitions = nil
        @plan = nil

        @document = if document.is_a?(String)
          @string = document
          GraphQL.parse(document)
        else
          document
        end

        @operation_name = operation_name
        @variables = variables || {}
        @context = context || GraphQL::Stitching::EMPTY_OBJECT
      end

      def string
        @string || normalized_string
      end

      def normalized_string
        @normalized_string ||= @document.to_query_string
      end

      def digest
        @digest ||= Digest::SHA2.hexdigest(string)
      end

      def normalized_digest
        @normalized_digest ||= Digest::SHA2.hexdigest(normalized_string)
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

      def operation_directives
        @operation_directives ||= if operation.directives.any?
          printer = GraphQL::Language::Printer.new
          operation.directives.map { printer.print(_1) }.join(" ")
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
          @variables[v.name] = v.default_value if @variables[v.name].nil? && !v.default_value.nil?
        end

        if @string.nil? || @string.match?(SKIP_INCLUDE_DIRECTIVE)
          SkipInclude.render(@document, @variables) do |modified_ast|
            @document = modified_ast
            @string = @normalized_string = nil
            @digest = @normalized_digest = nil
            @operation = @operation_directives = @variable_definitions = @plan = nil
          end
        end

        self
      end

      def plan(new_plan = nil)
        if new_plan
          raise StitchingError, "Plan must be a `GraphQL::Stitching::Plan`." unless new_plan.is_a?(Plan)
          @plan = new_plan
        else
          @plan ||= GraphQL::Stitching::Planner.new(self).perform
        end
      end

      def execute(raw: false)
        GraphQL::Stitching::Executor.new(self).perform(raw: raw)
      end
    end
  end
end
