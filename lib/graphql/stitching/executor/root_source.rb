# frozen_string_literal: true

module GraphQL::Stitching
  class Executor
    class RootSource < GraphQL::Dataloader::Source
      def initialize(executor, location)
        @executor = executor
        @location = location
      end

      def fetch(ops)
        op = ops.first # There should only ever be one per location at a time

        query_document = build_document(
          op,
          @executor.request.operation_name,
          @executor.request.operation_directives,
        )
        query_variables = @executor.request.variables.slice(*op.variables.each_key)
        result = @executor.request.supergraph.execute_at_location(op.location, query_document, query_variables, @executor.request)
        @executor.query_count += 1

        if result["data"]
          unless op.path.empty?
            # Nested root scopes must expand their pathed origin set
            origin_set = op.path.reduce([@executor.data]) do |set, ns|
              set.flat_map { |obj| obj && obj[ns] }.tap(&:compact!)
            end

            origin_set.each { _1.merge!(result["data"]) }
          else
            # Actual root scopes merge directly into results data
            @executor.data.merge!(result["data"])
          end
        end

        if result["errors"]&.any?
          @executor.errors.concat(format_errors!(result["errors"], op.path))
        end

        ops.map(&:step)
      end

      # Builds root source documents
      # "query MyOperation_1($var:VarType) { rootSelections ... }"
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

      # Format response errors without a document location (because it won't match the request doc),
      # and prepend any insertion path for the scope into error paths.
      def format_errors!(errors, path)
        errors.each do |err|
          err.delete("locations")
          err["path"].unshift(*path) if err["path"] && !path.empty?
        end
        errors
      end
    end
  end
end
