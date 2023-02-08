# frozen_string_literal: true

module GraphQL
  module Stitching
    class Composer::ValidateInterfaces < Composer::BaseValidator

      def perform(supergraph, composer)
        # @todo
        # Validate all supergraph interface fields
        # match possible types in all locations...
        # - Traverse supergraph types (supergraph.types)
        # - For each interface (.kind.interface?), get possible types (Util.get_possible_types)
        # - For each possible type, traverse type candidates (composer.subschema_types_by_name_and_location)
        # - For each type candidate, compare interface fields to type candidate fields
        # - For each type candidate field that matches an interface field...
        #   - Named types must match
        #   - List structures must match
        #   - Nullabilities must be >= interface field
        # - It's OKAY if a type candidate does not implement the full interface
      end

    end
  end
end
