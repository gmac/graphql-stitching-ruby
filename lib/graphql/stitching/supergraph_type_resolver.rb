# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    module SupergraphTypeResolver

      def resolve_type(_type, obj, _ctx)
        puts obj
        self.types[obj["_STITCH_typename"]]
      end

    end
  end
end
