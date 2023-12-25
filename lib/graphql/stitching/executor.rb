# frozen_string_literal: true

require "json"

module GraphQL
  module Stitching
    class Executor
      attr_reader :supergraph, :request, :plan, :data, :errors
      attr_accessor :query_count

      def initialize(request, nonblocking: false)
        @request = request
        @supergraph = request.supergraph
        @plan = request.plan
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
          result["data"] = raw ? @data : GraphQL::Stitching::Shaper.new(@request).perform!(@data)
        end

        if @errors.length > 0
          result["errors"] = @errors
        end

        result
      end

      private

      def exec!(next_steps = [0])
        if @exec_cycles > @plan.ops.length
          # sanity check... if we've exceeded queue size, then something went wrong.
          raise StitchingError, "Too many execution requests attempted."
        end

        @dataloader.append_job do
          tasks = @plan
            .ops
            .select { next_steps.include?(_1.after) }
            .group_by { [_1.location, _1.boundary.nil?] }
            .map do |(location, root_source), ops|
              source_type = root_source ? RootSource : BoundarySource
              @dataloader.with(source_type, self, location).request_all(ops)
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

require_relative "./executor/boundary_source"
require_relative "./executor/root_source"
