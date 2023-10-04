# frozen_string_literal: true

module GraphQL
  module Stitching
    class Executor::Payload
      attr_reader :root_typename, :path, :label

      def initialize(root_typename:, path:, steps_total:, label: nil)
        @root_typename = root_typename
        @path = path
        @label = label
        @data = {}
        @errors = []
        @steps_total = steps_total
        @steps_complete = 0
      end

      def complete?
        @steps_total == @steps_complete
      end
    end
  end
end
