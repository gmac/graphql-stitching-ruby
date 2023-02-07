# frozen_string_literal: true

require "json"

module GraphQL
  module Stitching
    class Executor

      class RootSource < GraphQL::Dataloader::Source
        def initialize(executor)
          @executor = executor
        end

        def fetch(ops)
          op = ops.first # There should only ever be one per location at a time
          variable_defs = op["variables"].map { |k, v| "$#{k}:#{v}" }.join(",")
          variable_defs = "(#{variable_defs})" if variable_defs.length > 0
          document = "#{op["operation_type"]}#{variable_defs}#{op["selections"]}"

          variables = @executor.variables.slice(*op["variables"].keys)
          result = @executor.supergraph.execute_at_location(op["location"], document, variables)
          @executor.query_count += 1

          @executor.data.merge!(result["data"]) if result["data"]
          @executor.errors.concat(result["errors"]) if result["errors"]&.any?
          op["key"]
        end
      end

      class BoundarySource < GraphQL::Dataloader::Source
        def initialize(executor, location)
          @executor = executor
          @location = location
        end

        def fetch(ops)
          origin_sets_by_operation = ops.each_with_object({}) do |op, memo|
            origin_set = op["insertion_path"].reduce([@executor.data]) do |set, path_segment|
              mapped = set.flat_map { |obj| obj && obj[path_segment] }
              mapped.compact!
              mapped
            end

            if op["type_condition"]
              # operations planned around unused fragment conditions should not trigger requests
              origin_set.select! { _1["_STITCH_typename"] == op["type_condition"] }
            end

            memo[op] = origin_set if origin_set.any?
          end

          if origin_sets_by_operation.any?
            query_document, variable_names = build_query(origin_sets_by_operation)
            variables = @executor.variables.slice(*variable_names)
            raw_result = @executor.supergraph.execute_at_location(@location, query_document, variables)
            @executor.query_count += 1

            merge_results!(origin_sets_by_operation, raw_result)

            errors = raw_result.dig("errors")
            @executor.errors.concat(extract_result_errors(origin_sets_by_operation, errors)) if errors&.any?
          end

          ops.map { origin_sets_by_operation[_1] ? _1["key"] : nil }
        end

        def build_query(origin_sets_by_operation)
          variable_defs = {}
          query_fields = origin_sets_by_operation.map.with_index do |(op, origin_set), batch_index|
            variable_defs.merge!(op["variables"])
            boundary = op["boundary"]
            key_selection = "_STITCH_#{boundary["selection"]}"

            if boundary["list"]
              input = JSON.generate(origin_set.map { _1[key_selection] })
              "_#{batch_index}_result: #{boundary["field"]}(#{boundary["arg"]}:#{input}) #{op["selections"]}"
            else
              origin_set.map.with_index do |origin_obj, index|
                input = JSON.generate(origin_obj[key_selection])
                "_#{batch_index}_#{index}_result: #{boundary["field"]}(#{boundary["arg"]}:#{input}) #{op["selections"]}"
              end
            end
          end

          query_document = if variable_defs.any?
            query_variables = variable_defs.map { |k, v| "$#{k}:#{v}" }.join(",")
            "query(#{query_variables}){ #{query_fields.join(" ")} }"
          else
            "query{ #{query_fields.join(" ")} }"
          end

          return query_document, variable_defs.keys
        end

        def merge_results!(origin_sets_by_operation, raw_result)
          origin_sets_by_operation.each_with_index do |(op, origin_set), batch_index|
            results = if op.dig("boundary", "list")
              raw_result.dig("data", "_#{batch_index}_result")
            else
              origin_set.map.with_index { |_, index| raw_result.dig("data", "_#{batch_index}_#{index}_result") }
            end

            next unless results&.any?

            origin_set.each_with_index do |origin_obj, index|
              origin_obj.merge!(results[index]) if results[index]
            end
          end
        end

        # https://spec.graphql.org/June2018/#sec-Errors
        def extract_result_errors(origin_sets_by_operation, errors)
          ops = origin_sets_by_operation.keys
          origin_sets = origin_sets_by_operation.values
          pathed_errors_by_op_index_and_object_id = {}

          errors_result = errors.each_with_object([]) do |err, memo|
            path = err["path"]

            if path && path.length > 0
              result_alias = /^_(\d+)(?:_(\d+))?_result$/.match(path.first.to_s)

              if result_alias
                err.delete("locations")
                path = err["path"] = path[1..-1]

                origin_obj = if result_alias[2]
                  origin_sets.dig(result_alias[1].to_i, result_alias[2].to_i)
                elsif path[0].is_a?(Integer) || /\d+/.match?(path[0].to_s)
                  origin_sets.dig(result_alias[1].to_i, path.shift.to_i)
                end

                if origin_obj
                  by_op_index = pathed_errors_by_op_index_and_object_id[result_alias[1].to_i] ||= {}
                  by_object_id = by_op_index[origin_obj.object_id] ||= []
                  by_object_id << err
                  next
                end
              end
            end

            memo << err
          end

          if pathed_errors_by_op_index_and_object_id.any?
            pathed_errors_by_op_index_and_object_id.each do |op_index, pathed_errors_by_object_id|
              repath_errors!(pathed_errors_by_object_id, ops.dig(op_index, "insertion_path"))
              errors_result.concat(pathed_errors_by_object_id.values)
            end
          end
          errors_result
        end

        # traverses forward through origin data, expanding arrays to follow all paths
        # any errors found for an origin object_id have their path prefixed by the object path
        def repath_errors!(pathed_errors_by_object_id, forward_path, current_path=[], root=@executor.data)
          current_path << forward_path.first
          forward_path = forward_path[1..-1]
          scope = root[current_path.last]

          if forward_path.any? && scope.is_a?(Array)
            scope.each_with_index do |element, index|
              inner_elements = element.is_a?(Array) ? element.flatten : [element]
              inner_elements.each do |inner_element|
                repath_errors!(pathed_errors_by_object_id, forward_path, [*current_path, index], inner_element)
              end
            end

          elsif forward_path.any?
            repath_errors!(pathed_errors_by_object_id, forward_path, [*current_path, index], scope)

          elsif scope.is_a?(Array)
            scope.each_with_index do |element, index|
              inner_elements = element.is_a?(Array) ? element.flatten : [element]
              inner_elements.each do |inner_element|
                errors = pathed_errors_by_object_id[inner_element.object_id]
                errors.each { _1["path"] = [*current_path, index, *_1["path"]] } if errors
              end
            end

          else
            errors = pathed_errors_by_object_id[scope.object_id]
            errors.each { _1["path"] = [*current_path, *_1["path"]] } if errors
          end
        end
      end

      attr_reader :supergraph, :data, :errors, :variables
      attr_accessor :query_count

      def initialize(supergraph:, plan:, variables: {}, nonblocking: false)
        @supergraph = supergraph
        @variables = variables
        @queue = plan["ops"]
        @data = {}
        @errors = []
        @query_count = 0
        @dataloader = GraphQL::Dataloader.new(nonblocking: nonblocking)
      end

      def perform(document=nil)
        exec!

        # run the shaper...

        result = {}
        result["data"] = @data if @data && @data.length > 0
        result["errors"] = @errors if @errors.length > 0
        result
      end

      private

      def exec!(after_key = 0)
        @dataloader.append_job do
          tasks = @queue.select { _1["after_key"] == after_key }.map do |op|
            if op["after_key"].zero?
              @dataloader.with(RootSource, self).request(op)
            else
              @dataloader.with(BoundarySource, self, op["location"]).request(op)
            end
          end

          tasks.each(&method(:exec_task))
        end
        @dataloader.run
      end

      def exec_task(task)
        next_key = task.load
        exec!(next_key) if next_key
      end
    end
  end
end
