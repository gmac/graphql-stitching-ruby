# frozen_string_literal: true

module GraphQL::Stitching
  class Executor
    # Utilities for traversing aggregate executor data along planned paths.
    module PathAccess
      private

      def path_objects(root, path)
        objects = []
        each_path_object(root, path) { |object| objects << object }
        objects
      end

      def each_path_object(scope, path, &block)
        return enum_for(:each_path_object, scope, path) unless block
        return if scope.nil?

        if path.empty?
          each_leaf_object(scope, &block)
        elsif scope.is_a?(Array)
          scope.each { |element| each_path_object(element, path, &block) }
        elsif scope.respond_to?(:[])
          path_segment = path.first
          each_path_object(scope[path_segment], path[1..-1], &block)
        end
      end

      def each_leaf_object(scope, &block)
        return if scope.nil?

        if scope.is_a?(Array)
          scope.each { |element| each_leaf_object(element, &block) }
        else
          yield(scope)
        end
      end

      def path_entries(root, path)
        entries = []
        each_path_entry(root, path) { |object, response_path| entries << [object, response_path] }
        entries
      end

      def each_path_entry(scope, path, response_path = [], &block)
        return enum_for(:each_path_entry, scope, path, response_path) unless block
        return if scope.nil?

        if path.empty?
          each_leaf_entry(scope, response_path, &block)
        elsif scope.is_a?(Array)
          scope.each_with_index do |element, index|
            each_path_entry(element, path, [*response_path, index], &block)
          end
        elsif scope.respond_to?(:[])
          path_segment = path.first
          each_path_entry(scope[path_segment], path[1..-1], [*response_path, path_segment], &block)
        end
      end

      def each_leaf_entry(scope, response_path, &block)
        return if scope.nil?

        if scope.is_a?(Array)
          scope.each_with_index do |element, index|
            each_leaf_entry(element, [*response_path, index], &block)
          end
        else
          yield(scope, response_path)
        end
      end

      def sanitized_error(error, path: nil)
        error.dup.tap do |formatted|
          formatted.delete("locations")
          formatted["path"] = path if path
        end
      end
    end
  end
end
