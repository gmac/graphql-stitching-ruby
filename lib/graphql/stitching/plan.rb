# frozen_string_literal: true

module GraphQL
  module Stitching
    # Immutable-ish structures representing a query plan.
    # May serialize to/from JSON.
    class Plan
      Op = Struct.new(
        :step,
        :after,
        :location,
        :operation_type,
        :selections,
        :variables,
        :path,
        :if_type,
        :resolver,
        keyword_init: true
      ) do
        def as_json
          {
            step: step,
            after: after,
            location: location,
            operation_type: operation_type,
            selections: selections,
            variables: variables,
            path: path,
            if_type: if_type,
            resolver: resolver
          }.tap(&:compact!)
        end
      end

      class << self
        def from_json(json)
          ops = json["ops"]
          ops = ops.map do |op|
            Op.new(
              step: op["step"],
              after: op["after"],
              location: op["location"],
              operation_type: op["operation_type"],
              selections: op["selections"],
              variables: op["variables"],
              path: op["path"],
              if_type: op["if_type"],
              resolver: op["resolver"],
            )
          end
          new(ops: ops)
        end
      end

      attr_reader :ops

      def initialize(ops: [])
        @ops = ops
      end

      def as_json
        { ops: @ops.map(&:as_json) }
      end
    end
  end
end