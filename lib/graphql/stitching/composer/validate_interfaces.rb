# frozen_string_literal: true

module GraphQL
  module Stitching
    class Composer::ValidateInterfaces < Composer::BaseValidator

      # For each composed interface, check the interface against each possible type
      # to assure that intersecting fields have compatible types, structures, and nullability.
      # Verifies compatibility of types that inherit interface contracts through merging.
      def perform(supergraph, composer)
        supergraph.schema.types.each do |type_name, interface_type|
          next unless interface_type.kind.interface?

          supergraph.schema.possible_types(interface_type).each do |possible_type|
            type_candidates_by_location = composer.subschema_types_by_name_and_location[possible_type.graphql_name]

            type_candidates_by_location.each do |location, candidate_type|
              intersecting_field_names = candidate_type.fields.keys & interface_type.fields.keys

              intersecting_field_names.each do |field_name|
                candidate_type_structure = Util.flatten_type_structure(candidate_type.fields[field_name].type)
                interface_type_structure = Util.flatten_type_structure(interface_type.fields[field_name].type)

                if candidate_type_structure.length != interface_type_structure.length
                  raise Composer::ValidationError, "Field type of #{candidate_type.graphql_name}.#{field_name} must match "\
                    "list structure of merged interface #{interface_type.graphql_name}.#{field_name}."
                end

                interface_type_structure.each_with_index do |istruct, index|
                  cstruct = candidate_type_structure[index]

                  if cstruct[:name] != istruct[:name]
                    raise Composer::ValidationError, "Field type of #{candidate_type.graphql_name}.#{field_name} must match "\
                      "merged interface #{interface_type.graphql_name}.#{field_name}."
                  end

                  if cstruct[:null] && !istruct[:null]
                    raise Composer::ValidationError, "Field type of #{candidate_type.graphql_name}.#{field_name} must match "\
                      "non-null status of merged interface #{interface_type.graphql_name}.#{field_name}."
                  end
                end
              end
            end
          end
        end
      end

    end
  end
end
