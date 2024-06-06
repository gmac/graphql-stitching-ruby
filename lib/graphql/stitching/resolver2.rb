# frozen_string_literal: true

module GraphQL
  module Stitching
    class Resolver
      class Argument
        attr_reader :name
        attr_reader :value
        attr_reader :type_name

        def initialize(name:, value:, type_name: nil, list: false, key: false)
          @name = name
          @value = value
          @type_name = type_name
          @list = list
          @key = key
        end

        def list?
          @list
        end

        def key?
          @key
        end
      end

      class ArgumentSet
        attr_reader :arguments

        def initialize(arguments)
          @arguments = arguments
        end
      end

      ArgumentSet.new([
        Argument.new(
          type_name: "_Key",
          list: true,
          name: "reps",
          value: ArgumentSet.new([
            Argument.new(
              name: "group",
              key: true,
              value: ["scope", "group"]
            ),
            Argument.new(
              name: "name",
              key: true,
              value: ["scope", "name"]
            ),
          ])
        ),
        Argument.new(
          type_name: "String",
          list: false,
          name: "other",
          value: "Sfoo"
        )
      ])

      # location name providing the resolver query.
      attr_reader :location

      # name of merged type fulfilled through this resolver.
      attr_reader :type_name

      # a key field to select from prior locations, sent as resolver argument.
      attr_reader :key

      # name of the root field to query.
      attr_reader :field

      # specifies when the resolver is a list query.
      attr_reader :list

      # name of the root field argument used to send the key.
      attr_reader :arg

      # type name of the root field argument used to send the key.
      attr_reader :arg_type_name

      # specifies that keys should be sent as JSON representations with __typename and key.
      attr_reader :representations

      def initialize(
        location:,
        type_name:,
        key:,
        field: nil,
        arguments: nil,
      )
        @location = location
        @type_name = type_name
        @key = key
        @field = field
        @arguments = arguments
      end

      def arguments

      end

      def as_json
        {
          location: location,
          type_name: type_name,
          key: key,
          field: field,
          list: list,
          arg: arg,
          arg_type_name: arg_type_name,
          representations: representations,
        }.tap(&:compact!)
      end
    end
  end
end
