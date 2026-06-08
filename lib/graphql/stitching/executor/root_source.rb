# frozen_string_literal: true
# typed: true

module GraphQL::Stitching
  class Executor
    class RootSource < GraphQL::Dataloader::Source
      include PathAccess

      #: (Executor executor, Location location) -> void
      def initialize(executor, location)
        @executor = executor #: Executor
        @location = location #: Location
      end

      #: (Array[Plan::Op] ops) -> Array[Integer]
      def fetch(ops)
        ops.map do |op|
          origin_set = op.path.empty? ? [@executor.data] : path_objects(@executor.data, op.path)

          query_document = build_document(
            op,
            @executor.request.operation_name,
            @executor.request.operation_directives,
          )
          query_variables = @executor.request.variables.select { |key, _value| op.variables.key?(key) }
          result = @executor.request.supergraph.execute_at_location(op.location, query_document, query_variables, @executor.request)
          @executor.query_count += 1

          errors = result["errors"]
          origin_entries = [] #: Array[OriginEntry]

          if errors && !errors.empty?
            origin_entries = op.path.empty? ? [[@executor.data, []]] : path_entries(@executor.data, op.path)
          end

          if result["data"]
            if op.path.empty?
              # Actual root scopes merge directly into results data
              @executor.data.merge!(result["data"])
            elsif !origin_set.empty?
              # Nested root scopes merge the same root payload into each pathed origin
              origin_set.each { |origin_obj| origin_obj.merge!(result["data"]) }
            end
          end

          if errors && !errors.empty?
            @executor.errors.concat(format_errors(errors, origin_entries, op.path))
          end

          op.step
        end
      end

      #: (Plan::Op op, ?String? operation_name, ?String? operation_directives) -> String
      def build_document(op, operation_name = nil, operation_directives = nil)
        doc_buffer = String.new
        doc_buffer << op.operation_type

        if operation_name
          doc_buffer << " " << operation_name << "_" << op.step.to_s
        end

        unless op.variables.empty?
          doc_buffer << "("
          op.variables.each_with_index do |(k, v), i|
            doc_buffer << "," unless i.zero?
            doc_buffer << "$" << k << ":" << v
          end
          doc_buffer << ")"
        end

        if operation_directives
          doc_buffer << " " << operation_directives << " "
        end

        doc_buffer << op.selections
        doc_buffer
      end

      #: (Array[GraphQLError] errors, Array[OriginEntry] origin_entries, ?ResponsePath fallback_path) -> Array[GraphQLError]
      def format_errors(errors, origin_entries, fallback_path = [])
        errors.flat_map do |err|
          path = err["path"]

          if path && !origin_entries.empty?
            origin_entries.map do |_origin_obj, origin_path|
              sanitized_error(err, path: origin_path + path)
            end
          elsif path && !fallback_path.empty?
            sanitized_error(err, path: fallback_path + path)
          else
            sanitized_error(err)
          end
        end
      end
    end
  end
end
