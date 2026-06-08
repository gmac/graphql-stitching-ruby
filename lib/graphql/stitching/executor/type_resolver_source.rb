# frozen_string_literal: true

module GraphQL::Stitching
  class Executor
    class TypeResolverSource < GraphQL::Dataloader::Source
      include PathAccess

      def initialize(executor, location)
        @executor = executor
        @location = location
      end

      def fetch(ops)
        origin_sets_by_operation = ops.each_with_object({}.compare_by_identity) do |op, memo|
          origin_set = path_objects(@executor.data, op.path)

          if op.if_type
            # operations planned around unused fragment conditions should not trigger requests
            origin_set.select! { |origin_obj| origin_obj[TypeResolver::TYPENAME_EXPORT_NODE.alias] == op.if_type }
          end

          memo[op] = origin_set unless origin_set.empty?
        end

        unless origin_sets_by_operation.empty?
          query_document, variable_names, generated_variables = build_document(
            origin_sets_by_operation,
            @executor.request.operation_name,
            @executor.request.operation_directives,
          )
          variables = generated_variables.merge(@executor.request.variables.slice(*variable_names))
          raw_result = @executor.request.supergraph.execute_at_location(@location, query_document, variables, @executor.request)
          @executor.query_count += 1

          merge_results!(origin_sets_by_operation, raw_result.dig("data"))

          errors = raw_result.dig("errors")
          @executor.errors.concat(extract_errors!(origin_sets_by_operation, errors)) if errors && !errors.empty?
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
        generated_variables = {}
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
                generated_variables[variable_name] = origin_set.map { arg.build(_1) }
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
                  generated_variables[variable_name] = arg.build(origin_obj)
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

        variable_names = variable_defs.keys.tap do |names|
          names.reject! { generated_variables.key?(_1) }
        end

        return doc_buffer, variable_names, generated_variables
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
      def extract_errors!(origin_sets_by_operation, errors, origin_paths_by_operation = nil)
        ops = origin_sets_by_operation.keys
        origin_sets = origin_sets_by_operation.values
        origin_paths_by_operation ||= origin_sets_by_operation.each_with_object({}.compare_by_identity) do |(op, origin_set), memo|
          memo[op] = paths_for_origin_set(op, origin_set)
        end

        errors.each_with_object([]) do |err, memo|
          path = err["path"]

          if path && path.length > 0
            result_alias = /^_(\d+)(?:_(\d+))?_result$/.match(path.first.to_s)

            if result_alias
              path = path[1..-1]
              batch_index = result_alias[1].to_i

              origin_index = if result_alias[2]
                result_alias[2].to_i
              elsif path[0].is_a?(Integer) || /\A\d+\z/.match?(path[0].to_s)
                path.shift.to_i
              end
              origin_obj = origin_sets.dig(batch_index, origin_index) if origin_index

              if origin_obj
                op = ops[batch_index]
                object_path = origin_paths_by_operation.dig(op, origin_index)

                if object_path
                  memo << sanitized_error(err, path: object_path + path)
                  next
                end
              end

              memo << sanitized_error(err, path: path)
              next
            end
          end

          memo << sanitized_error(err)
        end
      end

      private

      def paths_for_origin_set(op, origin_set)
        paths_by_object_id = path_entries(@executor.data, op.path).each_with_object(Hash.new { |h, k| h[k] = [] }) do |(object, path), memo|
          memo[object.object_id] << path
        end

        origin_set.map { |origin_obj| paths_by_object_id[origin_obj.object_id].shift }
      end
    end
  end
end
