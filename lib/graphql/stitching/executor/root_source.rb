# frozen_string_literal: true

module GraphQL
  module Stitching
    class Executor::RootSource < GraphQL::Dataloader::Source
      def initialize(executor, location)
        @executor = executor
        @location = location
      end

      def fetch(ops)
        op = ops.first # There should only ever be one per location at a time

        query_document = build_document(op, @executor.request.operation_name)
        query_variables = @executor.request.variables.slice(*op.variables.keys)
        result = @executor.supergraph.execute_at_location(op.location, query_document, query_variables, @executor.request.context)
        @executor.query_count += 1

        @executor.data.merge!(result["data"]) if result["data"]
        if result["errors"]&.any?
          result["errors"].each { _1.delete("locations") }
          @executor.errors.concat(result["errors"])
        end

        ops.map(&:step)
      end

      # Builds root source documents
      # "query MyOperation_1($var:VarType) { rootSelections ... }"
      def build_document(op, operation_name = nil)
        doc = String.new
        doc << op.operation_type

        if operation_name
          doc << " #{operation_name}_#{op.step}"
        end

        if op.variables.any?
          variable_defs = op.variables.map { |k, v| "$#{k}:#{v}" }.join(",")
          doc << "(#{variable_defs})"
        end

        doc << op.selections
        doc
      end
    end
  end
end
