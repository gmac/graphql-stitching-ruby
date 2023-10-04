# frozen_string_literal: true

require "json"

module GraphQL
  module Stitching
    class Executor
      attr_reader :supergraph, :request, :data, :errors
      attr_accessor :query_count # for testing

      def initialize(supergraph:, request:, plan:, nonblocking: false)
        @supergraph = supergraph
        @request = request
        @queue = plan.ops
        @payloads_by_label = {}
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
          result["data"] = raw ? @data : GraphQL::Stitching::Shaper.new(
            supergraph: @supergraph,
            request: @request,
          ).perform!(@data)
        end

        if @errors.length > 0
          result["errors"] = @errors
        end

        result
      end

      private

      def exec!(next_ordinals = [0])
        if @exec_cycles > @queue.length
          # sanity check... if we've exceeded queue size, then something went wrong.
          raise StitchingError, "Too many execution requests attempted."
        end

        @dataloader.append_job do
          tasks = @queue
            .select { next_ordinals.include?(_1.after) }
            .group_by { [_1.location, _1.boundary.nil?, _1.defer_label] }
            .map do |(location, root_source, defer_label), ops|
              if root_source
                @dataloader.with(RootSource, self, location, defer_label).request_all(ops)
              else
                @dataloader.with(BoundarySource, self, location, defer_label).request_all(ops)
              end
            end

          tasks.each(&method(:exec_task))
        end

        @exec_cycles += 1
        @dataloader.run
      end

      def exec_task(task)
        next_ordinals = task.load.tap(&:compact!)
        exec!(next_ordinals) if next_ordinals.any?
      end
    end
  end
end

require_relative "./executor/payload"
require_relative "./executor/boundary_source"
require_relative "./executor/root_source"
