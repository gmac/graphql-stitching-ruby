# frozen_string_literal: true
# typed: true

module GraphQL::Stitching
  class Composer
    class BaseValidator
      #: (Supergraph supergraph, Composer composer) -> void
      def perform(supergraph, composer)
        raise "not implemented"
      end
    end
  end
end
