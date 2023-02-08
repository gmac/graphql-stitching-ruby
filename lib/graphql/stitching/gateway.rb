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

      def register_cache_read(&block)
        @cache_read_hook = block
      end
      def register_cache_write(&block)
        @cache_write_hook = block
      end

      private
      def cache_read(key)
        if @cache_read_hook
          @cache_read_hook.call(key)
        end
      end

      def cache_write(key,payload)
        if @cache_write_hook
          @cache_write_hook.call(key, payload)
        end
      end
      def validate_query(document:)
        validation_errors = @supergraph.schema.validate(document.ast)
        if validation_errors.any?
          { errors: [validation_errors.map { |e| { message: e.message, path: e.path } }] }
        end
      end
    end
  end
end
