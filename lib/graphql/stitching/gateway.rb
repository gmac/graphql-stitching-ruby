# frozen_string_literal: true

require "json"

module GraphQL
  module Stitching
    class Gateway
      class GatewayError < StitchingError; end

      EMPTY_CONTEXT = {}.freeze

      attr_reader :supergraph

      def initialize(locations: nil, supergraph: nil)
        @supergraph = if locations && supergraph
          raise GatewayError, "Cannot provide both locations and a supergraph."
        elsif supergraph && !supergraph.is_a?(Supergraph)
          raise GatewayError, "Provided supergraph must be a GraphQL::Stitching::Supergraph instance."
        elsif supergraph
          supergraph
        elsif locations
          build_supergraph_from_locations_config(locations)
        else
          raise GatewayError, "No locations or supergraph provided."
        end
      end

      def execute(query:, variables: nil, operation_name: nil, context: EMPTY_CONTEXT, validate: true)
        document = GraphQL::Stitching::Document.new(query, variables: variables, operation_name: operation_name).prepare!

        if validate
          validation_errors = @supergraph.schema.validate(document.ast)
          return error_result(validation_errors) if validation_errors.any?
        end

        begin
          plan = fetch_plan(document, context) do
            GraphQL::Stitching::Planner.new(
              supergraph: @supergraph,
              document: document,
            ).perform.to_h
          end

          GraphQL::Stitching::Executor.new(
            supergraph: @supergraph,
            plan: plan,
            variables: document.variables,
          ).perform(document)
        rescue StandardError => e
          custom_message = @on_error.call(e, context) if @on_error
          error_result([{ "message" => custom_message || "An unexpected error occured." }])
        end
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

      def build_supergraph_from_locations_config(locations)
        schemas = locations.each_with_object({}) do |(location, config), memo|
          schema = config[:schema]
          if schema.nil?
            raise GatewayError, "A schema is required for `#{location}` location."
          elsif !(schema.is_a?(Class) && schema <= GraphQL::Schema)
            raise GatewayError, "The schema for `#{location}` location must be a GraphQL::Schema class."
          else
            memo[location.to_s] = schema
          end
        end

        supergraph = GraphQL::Stitching::Composer.new(schemas: schemas).perform

        locations.each do |location, config|
          executable = config[:executable]
          supergraph.assign_executable(location.to_s, executable) if executable
        end

        supergraph
      end

      def fetch_plan(document, context)
        if @on_cache_read
          cached_plan = @on_cache_read.call(document.digest, context)
          return JSON.parse(cached_plan) if cached_plan
        end

        plan_json = yield

        if @on_cache_write
          @on_cache_write.call(document.digest, JSON.generate(plan_json), context)
        end

        plan_json
      end

      def error_result(errors)
        public_errors = errors.map do |e|
          public_error = e.is_a?(Hash) ? e : e.to_h
          public_error["path"] ||= []
          public_error
        end

        { "errors" => public_errors }
      end
    end
  end
end
