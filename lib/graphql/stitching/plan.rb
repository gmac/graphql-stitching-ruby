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

      Error = Struct.new(
        :code,
        :path,
        keyword_init: true
      ) do
        def as_json
          {
            code: code,
            path: path,
          }
        end
      end

      class << self
        def from_json(json)
          ops = json["ops"].map do |op|
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

          errors = json["errors"]&.map do |err|
            Error.new(
              code: err["code"],
              path: err["path"],
            )
          end

          new(
            ops: ops,
            claims: json["claims"] || EMPTY_ARRAY, 
            errors: errors || EMPTY_ARRAY,
          )
        end
      end

      attr_reader :ops, :claims, :errors

      def initialize(ops: EMPTY_ARRAY, claims: nil, errors: nil)
        @ops = ops
        @claims = claims || EMPTY_ARRAY
        @errors = errors || EMPTY_ARRAY
      end

      def as_json
        {
          ops: @ops.map(&:as_json),
          claims: @claims,
          errors: @errors.map(&:as_json),
        }.tap(&:compact!)
      end
    end
  end
end
