# frozen_string_literal: true

module GraphQL
  module Stitching
    Boundary = Struct.new(
      :location,
      :type_name,
      :key,
      :field,
      :arg,
      :list,
      :federation,
      keyword_init: true
    ) do
      def as_json
        {
          location: location,
          type_name: type_name,
          key: key,
          field: field,
          arg: arg,
          list: list,
          federation: federation,
        }.tap(&:compact!)
      end
    end
  end
end
