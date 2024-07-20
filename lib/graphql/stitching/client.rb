# frozen_string_literal: true

require "json"

module GraphQL
  module Stitching
    # Client is an out-of-the-box helper that assembles all 
    # stitching components into a workflow that executes requests.
    class Client
      class ClientError < StitchingError; end

      # @return [Supergraph] composed supergraph that services incoming requests.
      attr_reader :supergraph

      # Builds a new client instance. Either `supergraph` or `locations` configuration is required.
      # @param supergraph [Supergraph] optional, a pre-composed supergraph that bypasses composer setup.
      # @param locations [Hash<Symbol, Hash<Symbol, untyped>>] optional, composer configurations for each graph location.
      # @param composer [Composer] optional, a pre-configured composer instance for use with `locations` configuration.
      def initialize(locations: nil, supergraph: nil, composer: nil)
        @supergraph = if locations && supergraph
          raise ClientError, "Cannot provide both locations and a supergraph."
        elsif supergraph && !supergraph.is_a?(Supergraph)
          raise ClientError, "Provided supergraph must be a GraphQL::Stitching::Supergraph instance."
        elsif supergraph
          supergraph
        else
          composer ||= Composer.new
          composer.perform(locations)
        end

        @on_cache_read = nil
        @on_cache_write = nil
        @on_error = nil
      end

      def execute(query:, variables: nil, operation_name: nil, context: nil, validate: true)
        request = Request.new(
          @supergraph,
          query,
          operation_name: operation_name,
          variables: variables,
          context: context,
        )

        if validate
          validation_errors = request.validate
          return error_result(validation_errors) if validation_errors.any?
        end

        request.prepare!
        load_plan(request)
        request.execute
      rescue GraphQL::ParseError, GraphQL::ExecutionError => e
        error_result([e])
      rescue StandardError => e
        custom_message = @on_error.call(request, e) if @on_error
        error_result([{ "message" => custom_message || "An unexpected error occured." }])
      end

      def on_cache_read(&block)
        raise ClientError, "A cache read block is required." unless block_given?
        @on_cache_read = block
      end

      def on_cache_write(&block)
        raise ClientError, "A cache write block is required." unless block_given?
        @on_cache_write = block
      end

      def on_error(&block)
        raise ClientError, "An error handler block is required." unless block_given?
        @on_error = block
      end

      private

      def load_plan(request)
        if @on_cache_read && plan_json = @on_cache_read.call(request)
          plan = Plan.from_json(JSON.parse(plan_json))

          # only use plans referencing current resolver versions
          if plan.ops.all? { |op| !op.resolver || @supergraph.resolvers_by_version[op.resolver] }
            return request.plan(plan)
          end
        end

        plan = request.plan

        if @on_cache_write
          @on_cache_write.call(request, JSON.generate(plan.as_json))
        end

        plan
      end

      def error_result(errors)
        public_errors = errors.map! do |e|
          e.is_a?(Hash) ? e : e.to_h
        end

        { "errors" => public_errors }
      end
    end
  end
end
