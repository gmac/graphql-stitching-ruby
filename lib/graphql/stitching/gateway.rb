# frozen_string_literal: true

require "json"

module GraphQL
  module Stitching
    class Gateway
      class GatewayError < StitchingError; end

      attr_reader :supergraph

      def initialize(locations: nil, supergraph: nil, composer: nil)
        @supergraph = if locations && supergraph
          raise GatewayError, "Cannot provide both locations and a supergraph."
        elsif supergraph && !supergraph.is_a?(GraphQL::Stitching::Supergraph)
          raise GatewayError, "Provided supergraph must be a GraphQL::Stitching::Supergraph instance."
        elsif supergraph
          supergraph
        else
          composer ||= GraphQL::Stitching::Composer.new
          composer.perform(locations)
        end
      end

      def execute(query:, variables: nil, operation_name: nil, context: nil, validate: true)
        request = GraphQL::Stitching::Request.new(
          query,
          operation_name: operation_name,
          variables: variables,
          context: context,
        )

        if validate
          validation_errors = @supergraph.schema.validate(request.document)
          return error_result(validation_errors) if validation_errors.any?
        end

        request.prepare!

        plan = fetch_plan(request) do
          GraphQL::Stitching::Planner.new(
            supergraph: @supergraph,
            request: request,
          ).perform.to_h
        end

        GraphQL::Stitching::Executor.new(
          supergraph: @supergraph,
          request: request,
          plan: plan,
        ).perform
      rescue GraphQL::ParseError, GraphQL::ExecutionError => e
        error_result([e])
      rescue StandardError => e
        custom_message = @on_error.call(e, request.context) if @on_error
        error_result([{ "message" => custom_message || "An unexpected error occured." }])
      end

      def on_cache_read(&block)
        raise GatewayError, "A cache read block is required." unless block_given?
        @on_cache_read = block
      end

      def on_cache_write(&block)
        raise GatewayError, "A cache write block is required." unless block_given?
        @on_cache_write = block
      end

      def on_error(&block)
        raise GatewayError, "An error handler block is required." unless block_given?
        @on_error = block
      end

      private

      def fetch_plan(request)
        if @on_cache_read
          cached_plan = @on_cache_read.call(request.digest, request.context)
          return JSON.parse(cached_plan) if cached_plan
        end

        plan_json = yield

        if @on_cache_write
          @on_cache_write.call(request.digest, JSON.generate(plan_json), request.context)
        end

        plan_json
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
