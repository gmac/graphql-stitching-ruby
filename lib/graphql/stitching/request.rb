# frozen_string_literal: true
# typed: true

require_relative "request/skip_include"

module GraphQL
  module Stitching
    class Request
      SKIP_INCLUDE_DIRECTIVE = /@(?:skip|include)/.freeze

      #: Supergraph
      attr_reader :supergraph

      #: GraphQL::Query
      attr_reader :query

      #: untyped
      attr_reader :context

      # @rbs!
      #   @prepared_document: DocumentNode?
      #   @string: String?
      #   @digest: String?
      #   @normalized_string: String?
      #   @normalized_digest: String?
      #   @operation: OperationNode?
      #   @operation_directives: String?
      #   @variable_definitions: VariableDefinitions?
      #   @fragment_definitions: FragmentDefinitions?
      #   @plan: Plan?
      #   @variables: Variables?

      #: (
      #|   Supergraph supergraph,
      #|   String | DocumentNode source,
      #|   ?operation_name: String?,
      #|   ?variables: Variables?,
      #|   ?context: untyped
      #| ) -> void
      def initialize(supergraph, source, operation_name: nil, variables: nil, context: nil)
        @supergraph = supergraph
        @prepared_document = nil
        @string = nil
        @digest = nil
        @normalized_string = nil
        @normalized_digest = nil
        @operation = nil
        @operation_directives = nil
        @variable_definitions = nil
        @fragment_definitions = nil
        @plan = nil

        params = {
          operation_name: operation_name,
          variables: variables,
          context: context,
        }

        if source.is_a?(String)
          @string = source
          params[:query] = source
        else
          params[:document] = source
        end

        @query = GraphQL::Query.new(@supergraph.schema, **params)
        @context = @query.context
        @context[:request] = self
      end

      #: -> DocumentNode
      def original_document
        @query.document
      end

      #: -> String
      def string
        with_prepared_document { @string || normalized_string }
      end

      #: -> String
      def normalized_string
        @normalized_string ||= prepared_document.to_query_string
      end

      #: -> String
      def digest
        @digest ||= Stitching.digest.call("#{Stitching::VERSION}/#{string}")
      end

      #: -> String
      def normalized_digest
        @normalized_digest ||= Stitching.digest.call("#{Stitching::VERSION}/#{normalized_string}")
      end

      #: -> OperationNode
      def operation
        @operation ||= with_prepared_document do
          selected_op = @query.selected_operation
          raise GraphQL::ExecutionError, "No operation selected" unless selected_op

          @prepared_document.definitions.find do |d|
            next unless d.is_a?(GraphQL::Language::Nodes::OperationDefinition)

            selected_op.name.nil? || d.name == selected_op.name
          end
        end
      end

      #: -> String?
      def operation_name
        operation.name
      end

      #: -> String?
      def operation_directives
        @operation_directives ||= unless operation.directives.empty?
          printer = GraphQL::Language::Printer.new
          operation.directives.map { printer.print(_1) }.join(" ")
        end
      end

      #: -> bool
      def query?
        @query.query?
      end

      #: -> bool
      def mutation?
        @query.mutation?
      end

      #: -> bool
      def subscription?
        @query.subscription?
      end

      #: -> Variables
      def variables
        @variables || with_prepared_document { @variables }
      end

      #: -> VariableDefinitions
      def variable_definitions
        @variable_definitions ||= operation.variables.each_with_object({}) do |v, memo|
          memo[v.name] = v.type
        end
      end

      #: -> FragmentDefinitions
      def fragment_definitions
        @fragment_definitions ||= prepared_document.definitions.each_with_object({}) do |d, memo|
          memo[d.name] = d if d.is_a?(GraphQL::Language::Nodes::FragmentDefinition)
        end
      end

      #: -> Array[GraphQL::ExecutionError]
      def validate
        @query.static_errors
      end

      #: -> bool
      def valid?
        validate.empty?
      end

      #: (?untyped new_plan) -> Plan
      def plan(new_plan = nil)
        if new_plan
          raise StitchingError, "Plan must be a `GraphQL::Stitching::Plan`." unless new_plan.is_a?(Plan)
          @plan = new_plan
        else
          @plan ||= Planner.new(self).perform
        end
      end

      #: (?raw: bool) -> GraphQL::Query::Result
      def execute(raw: false)
        add_subscription_update_handler if subscription?
        Executor.new(self).perform(raw: raw)
      end

      private

      #: -> DocumentNode
      def prepared_document
        @prepared_document || with_prepared_document { @prepared_document }
      end

      #: [T] () { () -> T } -> T
      def with_prepared_document(&block)
        unless @prepared_document
          @variables = @query.variables.to_h

          @prepared_document = if @string.nil? || @string.match?(SKIP_INCLUDE_DIRECTIVE)
            changed = false #: bool
            doc = SkipInclude.render(@query.document, @variables) { changed = true }
            @string = @normalized_string = doc.to_query_string if changed
            doc
          else
            @query.document
          end
        end
        block.call
      end

      #: -> void
      def add_subscription_update_handler
        request = self
        @context[:stitch_subscription_update] = -> (result) {
          stitched_result = Executor.new(
            request,
            data: result.to_h["data"] || {},
            errors: result.to_h["errors"] || [],
            after: request.plan.ops.fetch(0).step,
          ).perform

          result.to_h.merge!(stitched_result.to_h)
          result
        }
      end
    end
  end
end
