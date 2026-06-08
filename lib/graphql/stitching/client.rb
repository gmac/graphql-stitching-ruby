# frozen_string_literal: true
# typed: true

require "json"

module GraphQL
  module Stitching
    class Client
      class << self
        #: (String | singleton(GraphQL::Schema) schema, executables: Hash[Location | Symbol, Executable]) -> Client
        def from_definition(schema, executables:)
          new(supergraph: Supergraph.from_definition(schema, executables: executables))
        end
      end
      
      #: Supergraph
      attr_reader :supergraph

      #: (?locations: untyped, ?supergraph: Supergraph?, ?composer_options: Hash[Symbol, untyped]) -> void
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
          composer = Composer.new(**composer_options)
          composer.perform(locations)
        end

        @on_cache_read = nil #: CacheReadHandler?
        @on_cache_write = nil #: CacheWriteHandler?
        @on_error = nil #: ErrorHandler?
      end

      #: (
      #|   ?String | DocumentNode | nil raw_query,
      #|   ?query: String | DocumentNode | nil,
      #|   ?variables: Variables?,
      #|   ?operation_name: String?,
      #|   ?context: untyped,
      #|   ?validate: bool
      #| ) -> untyped
      def execute(raw_query = nil, query: nil, variables: nil, operation_name: nil, context: nil, validate: true)
        source = raw_query || query
        raise ArgumentError, "A query string or document is required." unless source

        request = Request.new(
          @supergraph,
          source,
          operation_name: operation_name,
          variables: variables,
          context: context,
        )

        if validate
          validation_errors = request.validate
          return error_result(request, validation_errors) unless validation_errors.empty?
        end

        load_plan(request)
        request.execute
      rescue GraphQL::ParseError, GraphQL::ExecutionError => e
        error_result(request, [e])
      rescue StandardError => e
        custom_message = @on_error.call(request, e) if @on_error
        error_result(request, [{ "message" => custom_message || "An unexpected error occured." }])
      end

      #: ?{ (Request) -> String? } -> CacheReadHandler
      def on_cache_read(&block)
        raise ArgumentError, "A cache read block is required." unless block
        @on_cache_read = block
      end

      #: ?{ (Request, String) -> void } -> CacheWriteHandler
      def on_cache_write(&block)
        raise ArgumentError, "A cache write block is required." unless block
        @on_cache_write = block
      end

      #: ?{ (Request?, StandardError) -> String? } -> ErrorHandler
      def on_error(&block)
        raise ArgumentError, "An error handler block is required." unless block
        @on_error = block
      end

      private

      #: (Request request) -> Plan
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

      #: (Request? request, Array[PublicErrorObject | PublicError] errors) -> GraphQL::Query::Result
      def error_result(request, errors)
        public_errors = errors.map! do |e|
          e.is_a?(Hash) ? e : e.to_h
        end

        GraphQL::Query::Result.new(query: request, values: { "errors" => public_errors })
      end
    end
  end
end
