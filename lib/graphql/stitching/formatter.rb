# frozen_string_literal: true

require_relative "type_resolver/arguments"
require_relative "type_resolver/keys"

module GraphQL
  module Stitching
    module Formatter
      class Default
        extend Formatter
      end

      class Info
        attr_reader :type_name, :field_name, :argument_name, :enum_value, :directive_name, :kwarg_name

        def initialize(
          type_name:,
          field_name: nil,
          argument_name: nil,
          enum_value: nil,
          directive_name: nil,
          kwarg_name: nil
        )
          @type_name = type_name
          @field_name = field_name
          @argument_name = argument_name
          @enum_value = enum_value
          @directive_name = directive_name
          @kwarg_name = kwarg_name
        end
      end

      def merge_values(values_by_location, _info)
        values_by_location.each_value.find { !_1.nil? }
      end

      def merge_descriptions(values_by_location, info)
        merge_values(values_by_location, info)
      end

      def merge_deprecations(values_by_location, info)
        merge_values(values_by_location, info)
      end

      def merge_default_values(values_by_location, info)
        merge_values(values_by_location, info)
      end

      def merge_kwargs(values_by_location, info)
        if info.directive_name == GraphQL::Stitching.visibility_directive
          values_by_location.each_value.reduce(:&)
        else
          merge_values(values_by_location, info)
        end
      end

      def build_graphql_error(_request, _err)
        { "message" => "An unexpected error occured." }
      end
    end
  end
end
