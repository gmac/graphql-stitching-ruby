# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    Boundary = Struct.new(
      :location,
      :selection,
      :field,
      :arg,
      :list,
      :type_name,
    ) do
      def as_json
        to_h
      end
    end
  end
end
