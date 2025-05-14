# frozen_string_literal: true

require_relative "request/skip_include"

module GraphQL
  module Stitching
    # Request combines a supergraph, GraphQL document, variables, 
    # variable/fragment definitions, and the selected operation.
    # It provides the lifecycle of validating, preparing,
    # planning, and executing upon these inputs.
    class Request
      SKIP_INCLUDE_DIRECTIVE = /@(?:skip|include)/

      # @return [Supergraph] supergraph instance that resolves the request.
      attr_reader :supergraph

      # @return [GraphQL::Query] query object defining the request.
      attr_reader :query

      # @return [Hash] contextual object passed through resolver flows.
      attr_reader :context

      # @return [Array[String]] authorization claims provided for the request.
      attr_reader :claims

      # Creates a new supergraph request.
      # @param supergraph [Supergraph] supergraph instance that resolves the request.
      # @param source [String, GraphQL::Language::Nodes::Document] the request string or parsed AST.
      # @param operation_name [String, nil] operation name selected for the request.
      # @param variables [Hash, nil] input variables for the request.
      # @param context [Hash, nil] a contextual object passed through resolver flows.
      def initialize(supergraph, source, operation_name: nil, variables: nil, context: nil, claims: nil)
        @supergraph = supergraph
        @claims = claims&.to_set&.freeze
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

      def original_document
        @query.document
      end

      # @return [String] the original document string, or a print of the parsed AST document.
      def string
        with_prepared_document { @string || normalized_string }
      end

      # @return [String] a print of the parsed AST document with consistent whitespace.
      def normalized_string
        @normalized_string ||= prepared_document.to_query_string
      end

      # @return [String] a digest of the original document string. Generally faster but less consistent.
      def digest
        @digest ||= Stitching.digest.call("#{Stitching::VERSION}/#{string}")
      end

      # @return [String] a digest of the normalized document string. Slower but more consistent.
      def normalized_digest
        @normalized_digest ||= Stitching.digest.call("#{Stitching::VERSION}/#{normalized_string}")
      end

      # @return [GraphQL::Language::Nodes::OperationDefinition] The selected root operation for the request.
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

      def operation_name
        operation.name
      end
      
      # @return [String] A string of directives applied to the root operation. These are passed through in all subgraph requests.
      def operation_directives
        @operation_directives ||= unless operation.directives.empty?
          printer = GraphQL::Language::Printer.new
          operation.directives.map { printer.print(_1) }.join(" ")
        end
      end

      # @return [Boolean] true if operation type is a query
      def query?
        @query.query?
      end

      # @return [Boolean] true if operation type is a mutation
      def mutation?
        @query.mutation?
      end

      # @return [Boolean] true if operation type is a subscription
      def subscription?
        @query.subscription?
      end

      # @return [Boolean] true if authorized to access field on type
      def authorized?(type_name, field_name)
        or_scopes = @supergraph.authorizations_by_type_and_field.dig(type_name, field_name)
        return true unless or_scopes&.any?
        return false unless @claims&.any?

        or_scopes.any? do |and_scopes|
          and_scopes.all? { |scope| @claims.include?(scope) }
        end
      end

      # @return [Hash<String, Any>] provided variables hash filled in with default values from definitions
      def variables
        @variables || with_prepared_document { @variables }
      end

      # @return [Hash<String, GraphQL::Language::Nodes::AbstractNode>] map of variable names to AST type definitions.
      def variable_definitions
        @variable_definitions ||= operation.variables.each_with_object({}) do |v, memo|
          memo[v.name] = v.type
        end
      end

      # @return [Hash<String, GraphQL::Language::Nodes::FragmentDefinition>] map of fragment names to their AST definitions.
      def fragment_definitions
        @fragment_definitions ||= prepared_document.definitions.each_with_object({}) do |d, memo|
          memo[d.name] = d if d.is_a?(GraphQL::Language::Nodes::FragmentDefinition)
        end
      end

      # Validates the request using the combined supergraph schema.
      # @return [Array<GraphQL::ExecutionError>] an array of static validation errors
      def validate
        @query.static_errors
      end

      # @return [Boolean] is the request valid?
      def valid?
        validate.empty?
      end

      # Gets and sets the query plan for the request. Assigned query plans may pull from a cache,
      # which is useful for redundant GraphQL documents (commonly sent by frontend clients).
      # ```ruby
      # if cached_plan = $cache.get(request.digest)
      #   plan = GraphQL::Stitching::Plan.from_json(JSON.parse(cached_plan))
      #   request.plan(plan)
      # else
      #   plan = request.plan
      #   $cache.set(request.digest, JSON.generate(plan.as_json))
      # end
      # ```
      # @param new_plan [Plan, nil] a cached query plan for the request.
      # @return [Plan] query plan for the request.
      def plan(new_plan = nil)
        if new_plan
          raise StitchingError, "Plan must be a `GraphQL::Stitching::Plan`." unless new_plan.is_a?(Plan)
          @plan = new_plan
        else
          @plan ||= Planner.new(self).perform
        end
      end

      # Executes the request and returns the rendered response.
      # @param raw [Boolean] specifies the result should be unshaped without pruning or null bubbling. Useful for debugging.
      # @return [Hash] the rendered GraphQL response with "data" and "errors" sections.
      def execute(raw: false)
        add_subscription_update_handler if subscription?
        Executor.new(self).perform(raw: raw)
      end

      private

      # Prepares the request for stitching by applying @skip/@include conditionals.
      def prepared_document
        @prepared_document || with_prepared_document { @prepared_document }
      end

      def with_prepared_document
        unless @prepared_document
          @variables = @query.variables.to_h

          @prepared_document = if @string.nil? || @string.match?(SKIP_INCLUDE_DIRECTIVE)
            changed = false
            doc = SkipInclude.render(@query.document, @variables) { changed = true }
            @string = @normalized_string = doc.to_query_string if changed
            doc
          else
            @query.document
          end
        end
        yield
      end

      # Adds a handler into context for enriching subscription updates with stitched data
      def add_subscription_update_handler
        request = self
        @context[:stitch_subscription_update] = -> (result) {
          stitched_result = Executor.new(
            request,
            data: result.to_h["data"] || {},
            errors: result.to_h["errors"] || [],
            after: request.plan.ops.first.step,
          ).perform

          result.to_h.merge!(stitched_result.to_h)
          result
        }
      end
    end
  end
end
