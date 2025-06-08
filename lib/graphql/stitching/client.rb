# frozen_string_literal: true

require "json"

module GraphQL
  module Stitching
    # Client is an out-of-the-box helper that assembles all 
    # stitching components into a workflow that executes requests.
    class Client
      include Formatter

      class << self
        def from_definition(schema, executables:)
          new(supergraph: Supergraph.from_definition(schema, executables: executables))
        end
      end
      
      # @return [Supergraph] composed supergraph that services incoming requests.
      attr_reader :supergraph

      # Builds a new client instance. Either `supergraph` or `locations` configuration is required.
      # @param supergraph [Supergraph] optional, a pre-composed supergraph that bypasses composer setup.
      # @param locations [Hash<Symbol, Hash<Symbol, untyped>>] optional, composer configurations for each graph location.
      # @param composer_options [Hash] optional, composer options for configuring composition.
      def initialize(locations: nil, supergraph: nil, composer_options: {})
        @supergraph = if locations && supergraph
          raise ArgumentError, "Cannot provide both locations and a supergraph."
        elsif supergraph && !supergraph.is_a?(Supergraph)
          raise ArgumentError, "Provided supergraph must be a GraphQL::Stitching::Supergraph instance."
        elsif supergraph && !composer_options.empty?
          raise ArgumentError, "Cannot provide composer options with a pre-built supergraph."
        elsif supergraph
          supergraph
        else
          composer_options = { formatter: self }.merge!(composer_options)
          composer = Composer.new(**composer_options)
          composer.perform(locations)
        end

        @on_cache_read = nil
        @on_cache_write = nil
        @on_error = nil
      end

      def execute(raw_query = nil, query: nil, variables: nil, operation_name: nil, context: nil, validate: true)
        request = Request.new(
          @supergraph,
          raw_query || query, # << for parity with GraphQL Ruby Schema.execute
          operation_name: operation_name,
          variables: variables,
          context: context,
        )

        if validate
          validation_errors = request.validate
          return error_result(request, validation_errors.map(&:to_h)) unless validation_errors.empty?
        end

        load_plan(request)
        request.execute
      rescue GraphQL::ParseError, GraphQL::ExecutionError => e
        error_result(request, [e.to_h])
      rescue StandardError => e
        @on_error.call(request, e) if @on_error
        error_result(request, [build_graphql_error(request, e)])
      end

      def on_cache_read(&block)
        raise ArgumentError, "A cache read block is required." unless block_given?
        @on_cache_read = block
      end

      def on_cache_write(&block)
        raise ArgumentError, "A cache write block is required." unless block_given?
        @on_cache_write = block
      end

      def on_error(&block)
        raise ArgumentError, "An error handler block is required." unless block_given?
        @on_error = block
      end

      def read_cached_plan(request)
        if @on_cache_read && (plan_json = @on_cache_read.call(request))
          Plan.from_json(JSON.parse(plan_json))
        end
      end

      def write_cached_plan(request, plan)
        @on_cache_write.call(request, JSON.generate(plan.as_json)) if @on_cache_write
      end

      private

      def load_plan(request)
        plan = read_cached_plan(request)

        # only use plans referencing current resolver versions
        if plan && plan.ops.all? { |op| !op.resolver || @supergraph.resolvers_by_version[op.resolver] }
          return request.plan(plan)
        end

        request.plan.tap do |plan|
          write_cached_plan(request, plan)
        end
      end

      def error_result(request, graphql_errors)
        GraphQL::Query::Result.new(query: request, values: { "errors" => graphql_errors })
      end
    end
  end
end
