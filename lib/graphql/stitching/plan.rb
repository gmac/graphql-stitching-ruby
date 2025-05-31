# frozen_string_literal: true

module GraphQL
  module Stitching
    # Immutable structures representing a query plan.
    # May serialize to/from JSON.
    class Plan
      class Op
        attr_reader :step
        attr_reader :after
        attr_reader :location
        attr_reader :operation_type
        attr_reader :selections
        attr_reader :variables
        attr_reader :path
        attr_reader :if_type
        attr_reader :resolver
        
        def initialize(
          step:,
          after:,
          location:,
          operation_type:,
          selections:,
          variables: nil,
          path: nil,
          if_type: nil,
          resolver: nil
        )
          @step = step
          @after = after
          @location = location
          @operation_type = operation_type
          @selections = selections
          @variables = variables
          @path = path
          @if_type = if_type
          @resolver = resolver
        end

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

        def ==(other)
          step == other.step &&
            after == other.after &&
            location == other.location &&
            operation_type == other.operation_type &&
            selections == other.selections &&
            variables == other.variables &&
            path == other.path &&
            if_type == other.if_type &&
            resolver == other.resolver
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