# frozen_string_literal: true

module GraphQL::Stitching
  class Composer
    class BaseValidator
      def perform(ctx, composer)
        raise "not implemented"
      end
    end
  end
end
