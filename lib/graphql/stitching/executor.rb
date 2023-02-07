# frozen_string_literal: true

require "json"

module GraphQL
  module Stitching
    class Executor

      attr_reader :query_count

      class RootSource < GraphQL::Dataloader::Source
        def fetch(ops)
          puts "root"
          puts ops
          ops
        end
      end

      class BoundarySource < GraphQL::Dataloader::Source
        def initialize(location)
          @location = location
        end

        def fetch(ops)
          puts "boundary #{@location}"
          puts ops
          ops.map { _1 > 10 ? nil : _1 }
        end
      end

      def initialize(supergraph:, plan:, variables:{})
        @supergraph = supergraph
        @queue = plan[:ops]
        @variables = variables
        @status = {}
        @data = {}
        @errors = []
        @query_count = 0
        @dataloader = GraphQL::Dataloader.new
      end

      def perform(document=nil)
        g2 = @queue[1].dup
        g2[:key] = 23
        @queue << g2
        pp @queue

        exec!


        # if document
        #   resolved = @supergraph.schema.execute(
        #     operation_name: document.operation_name,
        #     document: document.ast,
        #     variables: @variables,
        #     root_value: @data,
        #     validate: false,
        #   ).to_h

        #   @data = resolved.dig("data")
        #   @errors.concat(resolved.dig("errors")) if resolved.dig("errors")&.any?
        # end

        result = {}
        result["data"] = @data if @data && @data.length > 0
        result["errors"] = @errors if @errors.length > 0
        result
      end

      private

      def exec!(after_key = 0)
        @dataloader.append_job do
          reqs = @queue
            .select { _1[:after_key] == after_key }
            .map do |op|
              result = if op[:after_key].zero?
                @dataloader.with(RootSource).request(op[:key])
              else
                @dataloader.with(BoundarySource, op[:location]).request(op[:key])
              end
            end

          reqs.each do |req|
            result = req.load
            exec!(result) if result
          end
        end
        @dataloader.run
      end

      def query_root_location(ops)
        ops.each do |op|
          # @todo batch these requests as well
          variable_defs = op[:variables].map { |k, v| "$#{k}:#{v}" }.join(",")
          variable_defs = "(#{variable_defs})" if variable_defs.length > 0
          document = "#{op[:operation_type]}#{variable_defs}#{op[:selections]}"

          variables = @variables.slice(*op[:variables].keys)
          result = @supergraph.execute_at_location(op[:location], document, variables)
          @query_count += 1

          @data.merge!(result["data"]) if result["data"]
          @errors.concat(result["errors"]) if result["errors"]&.any?
          @status[op[:key]] = :completed
        end
      end

      def query_boundary_locations(ops)
        first_op = nil
        origin_sets_by_operation = ops.each_with_object({}) do |op, memo|
          first_op ||= op
          origin_set = op[:insertion_path].reduce([@data]) do |set, path_segment|
            mapped = set.flat_map { |obj| obj && obj[path_segment] }
            mapped.compact!
            mapped
          end

          if op[:type_condition]
            # operations planned around unused fragment conditions should not trigger requests
            origin_set.select! { _1["_STITCH_typename"] == op[:type_condition] }
          end

          if origin_set.any?
            memo[op] = origin_set
          else
            @status[op[:key]] = :skipped
          end
        end

        return unless origin_sets_by_operation.any?

        variable_defs = {}
        query_fields = origin_sets_by_operation.map.with_index do |(op, origin_set), batch_index|
          variable_defs.merge!(op[:variables])
          boundary = op[:boundary]
          key_selection = "_STITCH_#{boundary["selection"]}"

          if boundary["list"]
            input = JSON.generate(origin_set.map { _1[key_selection] })
            "_#{batch_index}_result: #{boundary["field"]}(#{boundary["arg"]}:#{input}) #{op[:selections]}"
          else
            origin_set.map.with_index do |origin_obj, index|
              input = JSON.generate(origin_obj[key_selection])
              "_#{batch_index}_#{index}_result: #{boundary["field"]}(#{boundary["arg"]}:#{input}) #{op[:selections]}"
            end
          end
        end

        query_document = if variable_defs.any?
          query_variables = variable_defs.map { |k, v| "$#{k}:#{v}" }.join(",")
          "#{first_op[:operation_type]}(#{query_variables}){ #{query_fields.join(" ")} }"
        else
          "#{first_op[:operation_type]}{ #{query_fields.join(" ")} }"
        end

        variables = @variables.slice(*variable_defs.keys)
        result = @supergraph.execute_at_location(first_op[:location], query_document, variables)
        @query_count += 1

        origin_sets_by_operation.each_with_index do |(op, origin_set), batch_index|
          boundary = op[:boundary]
          results = if boundary["list"]
            result.dig("data", "_#{batch_index}_result")
          else
            origin_set.map.with_index { |_, index| result.dig("data", "_#{batch_index}_#{index}_result") }
          end

          next unless results&.any?

          origin_set.each_with_index do |origin_obj, index|
            origin_obj.merge!(results[index]) if results[index]
          end

          @status[op[:key]] = :completed
        end

        errors = result.dig("errors")
        if errors&.any?
          @errors.concat(extract_result_errors(origin_sets_by_operation, errors))
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
            repath_errors!(pathed_errors_by_object_id, ops.dig(op_index, :insertion_path))
            errors_result.concat(pathed_errors_by_object_id.values)
          end
        end
        errors_result
      end

      # traverses forward through origin data, expanding arrays to follow all paths
      # any errors found for an origin object_id have their path prefixed by the object path
      def repath_errors!(pathed_errors_by_object_id, forward_path, current_path=[], root=@data)
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
  end
end
