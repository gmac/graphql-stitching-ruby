# frozen_string_literal: true

module GraphQL
  module Stitching
    class Request
      SUPPORTED_OPERATIONS = ["query", "mutation"].freeze
      EMPTY_CONTEXT = {}.freeze

      class ApplyRuntimeDirectives < GraphQL::Language::Visitor
        def initialize(document, variables)
          @changed = false
          @variables = variables
          super(document)
        end

        def changed?
          @changed
        end

        def on_field(node, parent)
          delete_node = false
          filtered_directives = if node.directives.any?
            node.directives.select do |directive|
              if directive.name == "skip"
                delete_node = assess_argument_value(directive.arguments.first)
                false
              elsif directive.name == "include"
                delete_node = !assess_argument_value(directive.arguments.first)
                false
              else
                true
              end
            end
          end

          if delete_node
            @changed = true
            super(DELETE_NODE, parent)
          elsif filtered_directives && filtered_directives.length != node.directives.length
            @changed = true
            super(node.merge(directives: filtered_directives), parent)
          else
            super
          end
        end

        private

        def assess_argument_value(arg)
          if arg.value.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
            return @variables[arg.value.name]
          end
          arg.value
        end
      end

      attr_reader :document, :variables, :operation_name, :context

      def initialize(document, variables: nil, operation_name: nil, context: nil)
        @document = if document.is_a?(String)
          GraphQL.parse(document)
        else
          document
        end

        @variables = variables || {}
        @operation_name = operation_name
        @context = context || EMPTY_CONTEXT
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
        @fragment_definitions ||= @document.definitions.each_with_object({}) do |d, memo|
          memo[d.name] = d if d.is_a?(GraphQL::Language::Nodes::FragmentDefinition)
        end
      end

      def prepare!
        operation.variables.each do |v|
          @variables[v.name] ||= v.default_value
        end

        visitor = ApplyRuntimeDirectives.new(@document, @variables)
        @document = visitor.visit

        if visitor.changed?
          @string = nil
          @digest = nil
        end
        self
      end
    end
  end
end
