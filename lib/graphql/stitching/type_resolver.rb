# frozen_string_literal: true
# typed: true

require_relative "type_resolver/arguments"
require_relative "type_resolver/keys"

module GraphQL
  module Stitching
    class TypeResolver
      extend ArgumentsParser
      extend KeysParser

      class << self
        #: -> bool
        def use_static_version?
          @use_static_version ||= false
        end
      end

      #: Location
      attr_reader :location

      #: TypeName?
      attr_reader :type_name

      #: FieldName?
      attr_reader :field

      #: Key?
      attr_reader :key

      #: Array[Argument]
      attr_reader :arguments

      #: (
      #|   location: Location,
      #|   ?type_name: TypeName?,
      #|   ?list: bool,
      #|   ?field: FieldName?,
      #|   ?key: Key?,
      #|   ?arguments: Array[Argument]?
      #| ) -> void
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
        @list = list #: bool
        @field = field
        @key = key
        @arguments = arguments || []
      end

      #: -> bool
      def list?
        @list
      end

      #: -> String
      def version
        @version ||= if self.class.use_static_version?
          [location, field, key&.to_definition, type_name].join(".")
        else
          Stitching.digest.call("#{Stitching::VERSION}/#{as_json.to_json}")
        end
      end

      #: (untyped other) -> bool
      def ==(other)
        self.class == other.class && self.as_json == other.as_json
      end

      #: -> JsonMap
      def as_json
        {
          location: location,
          type_name: type_name,
          list: list?,
          field: field,
          key: key&.to_definition,
          arguments: arguments.map(&:to_definition).join(", "),
          argument_types: arguments.map(&:to_type_definition).join(", "),
        }.tap(&:compact!)
      end

      #: -> String
      def inspect
        as_json.to_json
      end
    end
  end
end
