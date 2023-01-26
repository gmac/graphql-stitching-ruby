# frozen_string_literal: true

require "promise.rb"

module GraphQL
  module Stitching
    class Execute

      attr_reader :results

      def initialize(graph_info:, plan:, variables:{})
        @graph_info = graph_info
        @plan = plan
        @variables = variables
        @queue = plan[:ops].dup
        @results = {}
        @data = {}
        @errors = []
        @executor = ->(location, operation, variables) { raise "not implemented" }
      end

      def on_exec(&block)
        @executor = block
      end

      def perform
        exec_rec
      end

      private

      def exec_rec
        next_ops = []
        @queue.reject! do |op|
          after_key = op[:after_key]
          after_promise = @results[after_key]

          if after_key.nil? || after_promise #.complete?
            next_ops << op
            true
          end
        end

        next_ops.each do |op|
          @results[op[:key]] = true
          perform_operation(op) #.then { exec_rec }
        end

        if @results.length == @plan[:ops].length && @results.values.all? #(&:complete?)
          puts "done?"
          result = {}
          result[:data] = @data if @data
          result[:errors] = @errors if @errors.any?
          result
        else
          exec_rec
        end
      end

      def perform_operation(op)
        location = op[:location]
        boundary = op[:boundary]
        selections = op[:selections]
        operation_type = op[:operation_type]
        insertion_path = op[:insertion_path]

        if !boundary
          document = "#{operation_type} #{selections}"
          result = @executor.call(location, document, {})
          @data.merge!(result["data"]) if result["data"]
          @errors.concat(result["errors"]) if result["errors"]&.any?
        else
          original_set = insertion_path.reduce([@data]) do |set, path_segment|
            set.flat_map { |obj| obj && obj[path_segment] }.compact
          end

          results, errors = query_boundary_set(op, original_set)
          original_set.each_with_index do |origin_obj, index|
            origin_obj.merge!(results[index]) if results && results[index]
          end
        end
      end

      def query_boundary_set(op, origin_set)
        location = op[:location]
        boundary = op[:boundary]
        selections = op[:selections]
        operation_type = op[:operation_type]
        key_selection = "_STITCH_#{boundary["selection"]}"

        document = if boundary["list"]
          input = JSON.generate(origin_set.map { _1[key_selection] })
          "#{operation_type}{ _results: #{boundary["field"]}(#{boundary["arg"]}:#{input}) #{selections} }"
        else
          result_selections = origin_set.each_with_index.map do |origin_obj, index|
            input = JSON.generate(origin_obj[key_selection])
            "_#{index}_result: #{boundary["field"]}(#{boundary["arg"]}:#{input}) #{selections}"
          end

          "#{operation_type}{ #{result_selections.join(" ")} }"
        end

        result = @executor.call(location, document, {})

        if boundary["list"]
          return result.dig("data", "_results"), result.dig("errors")
        else
          results = origin_set.each_with_index.map do |_origin_obj, index|
            result.dig("data", "_#{index}_result")
          end
          return results, result.dig("errors")
        end
      end
    end
  end
end
