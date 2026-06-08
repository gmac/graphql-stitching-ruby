# frozen_string_literal: true
# typed: true

module GraphQL
  module Stitching
    class Plan
      class Op
        #: Integer
        attr_reader :step

        #: Integer?
        attr_reader :after

        #: Location
        attr_reader :location

        #: String
        attr_reader :operation_type

        #: String
        attr_reader :selections

        #: RenderedVariables
        attr_reader :variables

        #: Array[String]
        attr_reader :path

        #: TypeName?
        attr_reader :if_type

        #: String?
        attr_reader :resolver

        #: (
        #|   step: Integer,
        #|   after: Integer?,
        #|   location: Location,
        #|   operation_type: String,
        #|   selections: String,
        #|   ?variables: RenderedVariables?,
        #|   ?path: Array[String]?,
        #|   ?if_type: TypeName?,
        #|   ?resolver: String?
        #| ) -> void
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
          @variables = variables || {}
          @path = path || []
          @if_type = if_type
          @resolver = resolver
        end

        #: -> JsonMap
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

        #: (untyped other) -> bool
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
        #: (JsonMap json) -> Plan
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

      #: Array[Op]
      attr_reader :ops

      #: (?ops: Array[Op]) -> void
      def initialize(ops: [])
        @ops = ops
      end

      #: -> JsonMap
      def as_json
        { ops: @ops.map(&:as_json) }
      end
    end
  end
end
