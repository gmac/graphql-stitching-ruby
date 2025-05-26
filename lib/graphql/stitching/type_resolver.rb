# frozen_string_literal: true

require_relative "type_resolver/arguments"
require_relative "type_resolver/keys"

module GraphQL
  module Stitching
    # Defines a type resolver query that provides direct access to an entity type.
    class TypeResolver
      extend ArgumentsParser
      extend KeysParser

      class << self
        # only intended for testing...
        def use_static_version?
          @use_static_version ||= false
        end
      end

      # location name providing the resolver query.
      attr_reader :location

      # name of merged type fulfilled through this resolver.
      attr_reader :type_name

      # name of the root field to query.
      attr_reader :field

      # a key field to select from prior locations, sent as resolver argument.
      attr_reader :key

      # parsed resolver Argument structures.
      attr_reader :arguments

      def initialize(
        location:,
        type_name: nil,
        list: false,
        field: nil,
        key: nil,
        arguments: nil
      )
        @location = location
        @type_name = type_name
        @list = list
        @field = field
        @key = key
        @arguments = arguments
      end

      # specifies when the resolver is a list query.
      def list?
        @list
      end

      def version
        @version ||= if self.class.use_static_version?
          [location, field, key.to_definition, type_name].join(".")
        else
          Stitching.digest.call("#{Stitching::VERSION}/#{as_json.to_json}")
        end
      end

      def ==(other)
        self.class == other.class && self.as_json == other.as_json
      end

      def as_json
        {
          location: location,
          type_name: type_name,
          list: list?,
          field: field,
          key: key.to_definition,
          arguments: arguments.map(&:to_definition).join(", "),
          argument_types: arguments.map(&:to_type_definition).join(", "),
        }.tap(&:compact!)
      end

      def inspect
        as_json.to_json
      end
    end
  end
end
