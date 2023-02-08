# typed: false
# frozen_string_literal: true

# client is anything that accepts "call"
module GraphQL
  module Stitching
    class Gateway

      def initialize(schema_configurations:)
        schemas = {}
        remotes = {}
        schema_configurations.each do |schema_name, config|
          schemas[schema_name.to_s] = config[:schema]
          if config[:executable]
            remotes[schema_name.to_s] = config[:executable]
          end
        end
        @supergraph = GraphQL::Stitching::Composer.new(schemas: schemas).perform
        remotes.each do |location, executable|
          @supergraph.assign_executable(location, executable)
        end
      end

      def execute(query: nil, variables: {}, operation_name: nil, validate: true)
        doc = GraphQL::Stitching::Document.new(query, operation_name: operation_name)

        if validate && result = validate_query(document: doc)
          return result
        end

        plan = GraphQL::Stitching::Planner.new(
          supergraph: @supergraph,
          document: doc,
        ).perform

        GraphQL::Stitching::Executor.new(
          supergraph: @supergraph,
          plan: plan.to_h,
          variables: variables,
        ).perform(doc)
      end

      # should respond to call w/ key as an argument
      def cache_read(&block)
        @cache_read_block = block
      end

      # should respond to call w/ key and payload as arguments
      def cache_write(&block)
        @cache_write_block = block
      end

      private

      def validate_query(document:)
        validation_errors = @supergraph.schema.validate(document.ast)
        if validation_errors.any?
          { errors: [validation_errors.map { |e| { message: e.message, path: e.path } }] }
        end
      end
    end
  end
end
