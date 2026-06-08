# frozen_string_literal: true
# typed: true

require "json"
require_relative "executor/path_access"
require_relative "executor/root_source"
require_relative "executor/type_resolver_source"
require_relative "executor/shaper"

module GraphQL
  module Stitching
    class Executor
      #: Request
      attr_reader :request

      #: Data
      attr_reader :data

      #: Array[GraphQLError]
      attr_reader :errors

      #: Integer
      attr_accessor :query_count

      #: (Request request, ?data: Data, ?errors: Array[GraphQLError], ?after: Integer, ?nonblocking: bool) -> void
      def initialize(request, data: {}, errors: [], after: Planner::ROOT_INDEX, nonblocking: false)
        @request = request
        @data = data
        @errors = errors
        @after = after #: Integer
        @query_count = 0
        @exec_cycles = 0 #: Integer
        @dataloader = GraphQL::Dataloader.new(nonblocking: nonblocking) #: GraphQL::Dataloader
      end

      #: (?raw: bool) -> GraphQL::Query::Result
      def perform(raw: false)
        exec!([@after])
        result = {}

        if @data.length > 0
          result["data"] = raw ? @data : Shaper.new(@request).perform!(@data)
        end

        if @errors.length > 0
          result["errors"] = @errors
        end
        
        GraphQL::Query::Result.new(query: @request, values: result)
      end

      private

      #: (Array[Integer] next_steps) -> void
      def exec!(next_steps)
        if @exec_cycles > @request.plan.ops.length
          # sanity check... if we've exceeded queue size, then something went wrong.
          raise StitchingError, "Too many execution requests attempted."
        end

        @dataloader.append_job do
          requests = @request.plan
            .ops
            .select { next_steps.include?(_1.after) }
            .group_by { [_1.location, _1.resolver.nil?] }
            .map do |(location, root_source), ops|
              source_class = root_source ? RootSource : TypeResolverSource
              @dataloader.with(source_class, self, location).request_all(ops)
            end

          requests.each(&method(:exec_request))
        end

        @exec_cycles += 1
        @dataloader.run
      end

      #: (GraphQL::Dataloader::RequestAll request) -> void
      def exec_request(request)
        next_steps = request.load.tap(&:compact!)
        exec!(next_steps) unless next_steps.empty?
      end
    end
  end
end
