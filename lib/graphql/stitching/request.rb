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

      # @return [GraphQL::Language::Nodes::Document] the parsed GraphQL AST document.
      attr_reader :document

      # @return [Hash] input variables for the request.
      attr_reader :variables

      # @return [String] operation name selected for the request.
      attr_reader :operation_name

      # @return [Hash] contextual object passed through resolver flows.
      attr_reader :context

      # Creates a new supergraph request.
      # @param supergraph [Supergraph] supergraph instance that resolves the request.
      # @param document [String, GraphQL::Language::Nodes::Document] the request string or parsed AST.
      # @param operation_name [String, nil] operation name selected for the request.
      # @param variables [Hash, nil] input variables for the request.
      # @param context [Hash, nil] a contextual object passed through resolver flows.
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

        @query = GraphQL::Query.new(@supergraph.schema, document: @document, context: context)
        @context = @query.context
        @context[:request] = self
      end

      # @return [String] the original document string, or a print of the parsed AST document.
      def string
        @string || normalized_string
      end

      # @return [String] a print of the parsed AST document with consistent whitespace.
      def normalized_string
        @normalized_string ||= @document.to_query_string
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
        @operation ||= begin
          operation_defs = @document.definitions.select do |d|
            next unless d.is_a?(GraphQL::Language::Nodes::OperationDefinition)
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

      # @return [Boolean] true if operation type is a query
      def query?
        operation.operation_type == QUERY_OP
      end

      # @return [Boolean] true if operation type is a mutation
      def mutation?
        operation.operation_type == MUTATION_OP
      end

      # @return [Boolean] true if operation type is a subscription
      def subscription?
        operation.operation_type == SUBSCRIPTION_OP
      end

      # @return [String] A string of directives applied to the root operation. These are passed through in all subgraph requests.
      def operation_directives
        @operation_directives ||= if operation.directives.any?
          printer = GraphQL::Language::Printer.new
          operation.directives.map { printer.print(_1) }.join(" ")
        end
      end

      # @return [Hash<String, GraphQL::Language::Nodes::AbstractNode>] map of variable names to AST type definitions.
      def variable_definitions
        @variable_definitions ||= operation.variables.each_with_object({}) do |v, memo|
          memo[v.name] = v.type
        end
      end

      # @return [Hash<String, GraphQL::Language::Nodes::FragmentDefinition>] map of fragment names to their AST definitions.
      def fragment_definitions
        @fragment_definitions ||= @document.definitions.each_with_object({}) do |d, memo|
          memo[d.name] = d if d.is_a?(GraphQL::Language::Nodes::FragmentDefinition)
        end
      end

      # Validates the request using the combined supergraph schema.
      # @return [Array<GraphQL::ExecutionError>] an array of static validation errors
      def validate
        result = @supergraph.schema.static_validator.validate(@query)
        result[:errors]
      end

      # Prepares the request for stitching by inserting variable defaults and applying @skip/@include conditionals.
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
