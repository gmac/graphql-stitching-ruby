# frozen_string_literal: true

require "json"
require_relative "executor/root_source"
require_relative "executor/type_resolver_source"
require_relative "executor/shaper"

module GraphQL
  module Stitching
    # Executor handles executing upon a planned request.
    # All planned steps are initiated, their results merged,
    # and loaded keys are collected for batching subsequent steps.
    # Final execution results are then shaped to match the request selection.
    class Executor
      # @return [Request] the stitching request to execute.
      attr_reader :request

      # @return [Hash] an aggregate data payload to return.
      attr_reader :data

      # @return [Array<Hash>] aggregate GraphQL errors to return.
      attr_reader :errors

      # @return [Integer] tally of queries performed while executing.
      attr_accessor :query_count

      # Builds a new executor.
      # @param request [Request] the stitching request to execute.
      # @param nonblocking [Boolean] specifies if the dataloader should use async concurrency.
      def initialize(request, data: {}, errors: [], after: Planner::ROOT_INDEX, nonblocking: false)
        @request = request
        @data = data
        @errors = errors
        @after = after
        @query_count = 0
        @exec_cycles = 0
        @dataloader = GraphQL::Dataloader.new(nonblocking: nonblocking)
      end

      def perform(raw: false)
        exec!([@after])
        result = {}

        if @data && @data.length > 0
          result["data"] = raw ? @data : Shaper.new(@request).perform!(@data)
        end

        if @errors.length > 0
          result["errors"] = @errors
        end
        
        GraphQL::Query::Result.new(query: @request, values: result)
      end

      private

      def exec!(next_steps)
        if @exec_cycles > @request.plan.ops.length
          # sanity check... if we've exceeded queue size, then something went wrong.
          raise StitchingError, "Too many execution requests attempted."
        end

        @dataloader.append_job do
          tasks = @request.plan
            .ops
            .select { next_steps.include?(_1.after) }
            .group_by { [_1.location, _1.resolver.nil?] }
            .map do |(location, root_source), ops|
              source_class = root_source ? RootSource : TypeResolverSource
              @dataloader.with(source_class, self, location).request_all(ops)
            end

          tasks.each(&method(:exec_task))
        end

        @exec_cycles += 1
        @dataloader.run
      end

      def exec_task(task)
        next_steps = task.load.tap(&:compact!)
        exec!(next_steps) unless next_steps.empty?
      end
    end
  end
end
