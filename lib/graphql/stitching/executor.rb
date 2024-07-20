# frozen_string_literal: true

require "json"
require_relative "executor/resolver_source"
require_relative "executor/root_source"
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
      def initialize(request, nonblocking: false)
        @request = request
        @data = {}
        @errors = []
        @query_count = 0
        @exec_cycles = 0
        @dataloader = GraphQL::Dataloader.new(nonblocking: nonblocking)
      end

      def perform(raw: false)
        exec!
        result = {}

        if @data && @data.length > 0
          result["data"] = raw ? @data : Shaper.new(@request).perform!(@data)
        end

        if @errors.length > 0
          result["errors"] = @errors
        end

        result
      end

      private

      def exec!(next_steps = [0])
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
              source_class = root_source ? RootSource : ResolverSource
              @dataloader.with(source_class, self, location).request_all(ops)
            end

          tasks.each(&method(:exec_task))
        end

        @exec_cycles += 1
        @dataloader.run
      end

      def exec_task(task)
        next_steps = task.load.tap(&:compact!)
        exec!(next_steps) if next_steps.any?
      end
    end
  end
end
