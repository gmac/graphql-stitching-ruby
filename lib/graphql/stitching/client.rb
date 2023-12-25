# frozen_string_literal: true

require "json"

module GraphQL
  module Stitching
    class Client
      class ClientError < StitchingError; end

      attr_reader :supergraph

      def initialize(locations: nil, supergraph: nil, composer: nil)
        @supergraph = if locations && supergraph
          raise ClientError, "Cannot provide both locations and a supergraph."
        elsif supergraph && !supergraph.is_a?(GraphQL::Stitching::Supergraph)
          raise ClientError, "Provided supergraph must be a GraphQL::Stitching::Supergraph instance."
        elsif supergraph
          supergraph
        else
          composer ||= GraphQL::Stitching::Composer.new
          composer.perform(locations)
        end

        @on_cache_read = nil
        @on_cache_write = nil
        @on_error = nil
      end

      def execute(query:, variables: nil, operation_name: nil, context: nil, validate: true)
        request = GraphQL::Stitching::Request.new(
          @supergraph,
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
        request.plan = fetch_plan(request) { request.plan }
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

      def fetch_plan(request)
        if @on_cache_read
          cached_plan = @on_cache_read.call(request)
          return GraphQL::Stitching::Plan.from_json(JSON.parse(cached_plan)) if cached_plan
        end

        plan = yield

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
