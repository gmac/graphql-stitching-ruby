# frozen_string_literal: true

module GraphQL::Stitching
  class Executor
    class TypeResolverSource < GraphQL::Dataloader::Source
      def initialize(executor, location)
        @executor = executor
        @location = location
        @variables = {}
      end

      def fetch(ops)
        origin_sets_by_operation = ops.each_with_object({}.compare_by_identity) do |op, memo|
          origin_set = op.path.reduce([@executor.data]) do |set, path_segment|
            set.flat_map { |obj| obj && obj[path_segment] }.tap(&:compact!)
          end

          if op.if_type
            # operations planned around unused fragment conditions should not trigger requests
            origin_set.select! { _1[TypeResolver::TYPENAME_EXPORT_NODE.alias] == op.if_type }
          end

          memo[op] = origin_set unless origin_set.empty?
        end

        unless origin_sets_by_operation.empty?
          query_document, variable_names = build_document(
            origin_sets_by_operation,
            @executor.request.operation_name,
            @executor.request.operation_directives,
          )
          variables = @variables.merge!(@executor.request.variables.slice(*variable_names))
          raw_result = @executor.request.supergraph.execute_at_location(@location, query_document, variables, @executor.request)
          @executor.query_count += 1

          merge_results!(origin_sets_by_operation, raw_result.dig("data"))

          errors = raw_result.dig("errors")
          @executor.errors.concat(extract_errors!(origin_sets_by_operation, errors)) if errors&.any?
        end

        ops.map { origin_sets_by_operation[_1] ? _1.step : nil }
      end

      # Builds batched resolver queries
      # "query MyOperation_2_3($var:VarType, $_0_key:[ID!]!, $_1_0_key:ID!, $_1_1_key:ID!, $_1_2_key:ID!) {
      #   _0_result: list(keys: $_0_key) { resolverSelections... }
      #   _1_0_result: item(key: $_1_0_key) { resolverSelections... }
      #   _1_1_result: item(key: $_1_1_key) { resolverSelections... }
      #   _1_2_result: item(key: $_1_2_key) { resolverSelections... }
      # }"
      def build_document(origin_sets_by_operation, operation_name = nil, operation_directives = nil)
        variable_defs = {}
        fields_buffer = String.new

        origin_sets_by_operation.each_with_index do |(op, origin_set), batch_index|
          variable_defs.merge!(op.variables)
          resolver = @executor.request.supergraph.resolvers_by_version[op.resolver]
          fields_buffer << " " unless batch_index.zero?

          if resolver.list?
            fields_buffer << "_" << batch_index.to_s << "_result: " << resolver.field << "("

            resolver.arguments.each_with_index do |arg, i|
              fields_buffer << "," unless i.zero?
              if arg.key?
                variable_name = "_#{batch_index}_key_#{i}".freeze
                @variables[variable_name] = origin_set.map { arg.build(_1) }
                variable_defs[variable_name] = arg.to_type_signature
                fields_buffer << arg.name << ":$" << variable_name
              else
                fields_buffer << arg.name << ":" << arg.value.print
              end
            end

            fields_buffer << ") " << op.selections
          else
            origin_set.each_with_index do |origin_obj, index|
              fields_buffer << " " unless index.zero?
              fields_buffer << "_" << batch_index.to_s << "_" << index.to_s << "_result: " << resolver.field << "("

              resolver.arguments.each_with_index do |arg, i|
                fields_buffer << "," unless i.zero?
                if arg.key?
                  variable_name = "_#{batch_index}_#{index}_key_#{i}".freeze
                  @variables[variable_name] = arg.build(origin_obj)
                  variable_defs[variable_name] = arg.to_type_signature
                  fields_buffer << arg.name << ":$" << variable_name
                else
                  fields_buffer << arg.name << ":" << arg.value.print
                end
              end

              fields_buffer << ") " << op.selections
            end
          end
        end

        doc_buffer = String.new(QUERY_OP) # << resolver fulfillment always uses query

        if operation_name
          doc_buffer << " " << operation_name
          origin_sets_by_operation.each_key do |op|
            doc_buffer << "_" << op.step.to_s
          end
        end

        unless variable_defs.empty?
          doc_buffer << "("
          variable_defs.each_with_index do |(k, v), i|
            doc_buffer << "," unless i.zero?
            doc_buffer << "$" << k << ":" << v
          end
          doc_buffer << ")"
        end

        if operation_directives
          doc_buffer << " " << operation_directives << " "
        end

        doc_buffer << "{ " << fields_buffer << " }"

        return doc_buffer, variable_defs.keys.tap do |names|
          names.reject! { @variables.key?(_1) }
        end
      end

      def merge_results!(origin_sets_by_operation, raw_result)
        return unless raw_result

        origin_sets_by_operation.each_with_index do |(op, origin_set), batch_index|
          results = if @executor.request.supergraph.resolvers_by_version[op.resolver].list?
            raw_result["_#{batch_index}_result"]
          else
            origin_set.map.with_index { |_, index| raw_result["_#{batch_index}_#{index}_result"] }
          end

          next if results.nil? || results.empty?

          origin_set.each_with_index do |origin_obj, index|
            result = results[index]
            origin_obj.merge!(result) if result
          end
        end
      end

      # https://spec.graphql.org/June2018/#sec-Errors
      def extract_errors!(origin_sets_by_operation, errors)
        ops = origin_sets_by_operation.keys
        origin_sets = origin_sets_by_operation.values
        pathed_errors_by_op_index_and_object_id = Hash.new { |h, k| h[k] = {} }

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
                pathed_errors_by_op_index = pathed_errors_by_op_index_and_object_id[result_alias[1].to_i]
                by_object_id = pathed_errors_by_op_index[origin_obj.object_id] ||= []
                by_object_id << err
                next
              end
            end
          end

          memo << err
        end

        unless pathed_errors_by_op_index_and_object_id.empty?
          pathed_errors_by_op_index_and_object_id.each do |op_index, pathed_errors_by_object_id|
            repath_errors!(pathed_errors_by_object_id, ops[op_index].path)
            errors_result.push(*pathed_errors_by_object_id.each_value)
          end
        end

        errors_result.tap(&:flatten!)
      end

      private

      # traverse forward through origin data, expanding arrays to follow all paths
      # any errors found for an origin object_id have their path prefixed by the object path
      def repath_errors!(pathed_errors_by_object_id, forward_path, current_path=[], root=@executor.data)
        current_path.push(forward_path.shift)
        scope = root[current_path.last]

        if !forward_path.empty? && scope.is_a?(Array)
          scope.each_with_index do |element, index|
            inner_elements = element.is_a?(Array) ? element.flatten : [element]
            inner_elements.each do |inner_element|
              current_path << index
              repath_errors!(pathed_errors_by_object_id, forward_path, current_path, inner_element)
              current_path.pop
            end
          end

        elsif !forward_path.empty?
          repath_errors!(pathed_errors_by_object_id, forward_path, current_path, scope)

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
  end
end
