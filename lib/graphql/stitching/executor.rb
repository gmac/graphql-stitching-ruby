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

          query_document = build_query(op)
          query_variables = @executor.request.variables.slice(*op["variables"].keys)
          result = @executor.supergraph.execute_at_location(op["location"], query_document, query_variables, @executor.request.context)
          @executor.query_count += 1

          @executor.data.merge!(result["data"]) if result["data"]
          if result["errors"]&.any?
            result["errors"].each { _1.delete("locations") }
            @executor.errors.concat(result["errors"])
          end
          op["key"]
        end

        def build_query(op)
          if op["variables"].any?
            variable_defs = op["variables"].map { |k, v| "$#{k}:#{v}" }.join(",")
            "#{op["operation_type"]}(#{variable_defs})#{op["selections"]}"
          else
            "#{op["operation_type"]}#{op["selections"]}"
          end
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
            variables = @executor.request.variables.slice(*variable_names)
            raw_result = @executor.supergraph.execute_at_location(@location, query_document, variables, @executor.request.context)
            @executor.query_count += 1

            merge_results!(origin_sets_by_operation, raw_result.dig("data"))

            errors = raw_result.dig("errors")
            @executor.errors.concat(extract_errors!(origin_sets_by_operation, errors)) if errors&.any?
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
          return unless raw_result

          origin_sets_by_operation.each_with_index do |(op, origin_set), batch_index|
            results = if op.dig("boundary", "list")
              raw_result["_#{batch_index}_result"]
            else
              origin_set.map.with_index { |_, index| raw_result["_#{batch_index}_#{index}_result"] }
            end

            next unless results&.any?

            origin_set.each_with_index do |origin_obj, index|
              origin_obj.merge!(results[index]) if results[index]
            end
          end
        end

        # https://spec.graphql.org/June2018/#sec-Errors
        def extract_errors!(origin_sets_by_operation, errors)
          ops = origin_sets_by_operation.keys
          origin_sets = origin_sets_by_operation.values
          pathed_errors_by_op_index_and_object_id = {}

          errors_result = errors.each_with_object([]) do |err, memo|
            err.delete("locations")
            path = err["path"]

            if path && path.length > 0
              result_alias = /^_(\d+)(?:_(\d+))?_result$/.match(path.first.to_s)

              if result_alias
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
          errors_result.flatten!
        end

        private

        # traverse forward through origin data, expanding arrays to follow all paths
        # any errors found for an origin object_id have their path prefixed by the object path
        def repath_errors!(pathed_errors_by_object_id, forward_path, current_path=[], root=@executor.data)
          current_path.push(forward_path.shift)
          scope = root[current_path.last]

          if forward_path.any? && scope.is_a?(Array)
            scope.each_with_index do |element, index|
              inner_elements = element.is_a?(Array) ? element.flatten : [element]
              inner_elements.each do |inner_element|
                current_path << index
                repath_errors!(pathed_errors_by_object_id, forward_path, current_path, inner_element)
                current_path.pop
              end
            end

          elsif forward_path.any?
            current_path << index
            repath_errors!(pathed_errors_by_object_id, forward_path, current_path, scope)
            current_path.pop

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

          forward_path.unshift(current_path.pop)
        end
      end

      attr_reader :supergraph, :request, :data, :errors
      attr_accessor :query_count

      def initialize(supergraph:, request:, plan:, nonblocking: false)
        @supergraph = supergraph
        @request = request
        @queue = plan["ops"]
        @data = {}
        @errors = []
        @query_count = 0
        @dataloader = GraphQL::Dataloader.new(nonblocking: nonblocking)
      end

      def perform(raw: false)
        exec!

        result = {}
        result["data"] = @data if @data && @data.length > 0
        result["errors"] = @errors if @errors.length > 0

        if result["data"] && !raw
          GraphQL::Stitching::Shaper.new(
            schema: @supergraph.schema,
            request: @request,
          ).perform!(result)
        else
          result
        end
      end

      private

      def exec!(after_keys = [0])
        @dataloader.append_job do
          tasks = @queue
            .select { after_keys.include?(_1["after_key"]) }
            .group_by { _1["location"] }
            .map do |location, ops|
              if ops.first["after_key"].zero?
                @dataloader.with(RootSource, self).request_all(ops)
              else
                @dataloader.with(BoundarySource, self, location).request_all(ops)
              end
            end

          tasks.each(&method(:exec_task))
        end
        @dataloader.run
      end

      def exec_task(task)
        next_keys = task.load
        next_keys.compact!
        exec!(next_keys) if next_keys.any?
      end
    end
  end
end
