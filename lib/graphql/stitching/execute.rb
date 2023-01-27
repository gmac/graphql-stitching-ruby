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
          exec_rec
        end

        byebug
        if @results.length == @plan[:ops].length && @results.values.all? #(&:complete?)
          { data: @data, errors: @errors }
        end
      end

      def perform_operation(op)
        location = op[:location]
        boundary = op[:boundary]
        selections = op[:selections]
        operation_type = op[:operation_type]
        insertion_path = op[:insertion_path]

        if !boundary
          variable_defs = op[:variables].map { |k, v| "$#{k}:#{v}" }.join(",")
          variable_defs = "(#{variable_defs})" if variable_defs.length > 0
          document = "#{operation_type}#{variable_defs}#{selections}"
          variables = @variables.slice(*op[:variables].keys)

          result = @graph_info.get_client(location).call(document, variables, location)
          @data.merge!(result["data"]) if result["data"]
          @errors.concat(result["errors"]) if result["errors"]&.any?
        else
          original_set = insertion_path.reduce([@data]) do |set, path_segment|
            set.flat_map { |obj| obj && obj[path_segment] }.compact
          end

          results, errors = query_boundary_set(op, original_set, insertion_path)
          original_set.each_with_index do |origin_obj, index|
            origin_obj.merge!(results[index]) if results && results[index]
          end
        end
      end

      def query_boundary_set(op, origin_set, insertion_path)
        location = op[:location]
        boundary = op[:boundary]
        selections = op[:selections]
        operation_type = op[:operation_type]
        key_selection = "_STITCH_#{boundary["selection"]}"

        variable_defs = op[:variables].map { |k, v| "$#{k}:#{v}" }.join(",")
        variable_defs = "(#{variables})" if variables.length > 0

        document = if boundary["list"]
          input = JSON.generate(origin_set.map { _1[key_selection] })
          "#{operation_type}#{variable_defs}{ _STITCH_result: #{boundary["field"]}(#{boundary["arg"]}:#{input}) #{selections} }"
        else
          result_selections = origin_set.each_with_index.map do |origin_obj, index|
            input = JSON.generate(origin_obj[key_selection])
            "_STITCH_result_#{index}: #{boundary["field"]}(#{boundary["arg"]}:#{input}) #{selections}"
          end

          "#{operation_type}#{variable_defs}{ #{result_selections.join(" ")} }"
        end

        variables = @variables.slice(*op[:variables].keys)
        result = @graph_info.get_client(location).call(document, variables, location)

        if boundary["list"]
          errors = extract_list_result_errors(origin_set, insertion_path, result.dig("errors"))
          return result.dig("data", "_STITCH_result"), errors
        else
          results = origin_set.each_with_index.map do |_origin_obj, index|
            result.dig("data", "_STITCH_result_#{index}")
          end
          errors = extract_single_result_errors(origin_set, insertion_path, result.dig("errors"))
          return results, errors
        end
      end

      # https://spec.graphql.org/June2018/#sec-Errors
      def extract_list_result_errors(origin_set, insertion_path, errors)
        return nil unless errors&.any?
        pathed_errors_by_object_id = {}
        errors_result = []

        errors.each do |err|
          path = err["path"]
          if path && path.first == "_STITCH_result"
            path.shift
            if path.first && /^\d+$/.match?(path.first.to_s)
              index = path.shift
              origin = origin_set[index.to_i]
              if origin
                pathed_errors_by_object_id[origin.object_id] ||= []
                pathed_errors_by_object_id[origin.object_id] << err
                next
              end
            end
          end
          errors_result << err
        end

        if pathed_errors_by_object_id.any?
          repath_errors!(pathed_errors_by_object_id, insertion_path)
          errors_result.concat(pathed_errors_by_object_id.values)
        end
        errors_result
      end

      # https://spec.graphql.org/June2018/#sec-Errors
      def extract_single_result_errors(origin_set, insertion_path, errors)
        return nil unless errors&.any?

        pathed_errors_by_object_id = {}
        result_errors = errors.each_with_object([]) do |err, memo|
          path = err["path"]
          if path && path.length > 0
            result_index = /^_STITCH_result_(\d+)$/.match(path.first.to_s)
            if result_index
              path.shift
              origin = origin_set[result_index[1].to_i]
              if origin
                pathed_errors_by_object_id[origin.object_id] ||= []
                pathed_errors_by_object_id[origin.object_id] << err
                next
              end
            end
          end
          memo << err
        end

        if pathed_errors_by_object_id.any?
          repath_errors!(pathed_errors_by_object_id, insertion_path)
          result_errors.concat(pathed_errors_by_object_id.values)
        end
        result_errors
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
              errors.each { _1.path = [*current_path, index, *_1.path] } if errors
            end
          end

        else
          errors = pathed_errors_by_object_id[scope.object_id]
          errors.each { _1.path = [*current_path, *_1.path] } if errors
        end
      end
    end
  end
end
