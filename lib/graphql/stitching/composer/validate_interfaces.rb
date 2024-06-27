# frozen_string_literal: true

module GraphQL::Stitching
  class Composer
    class ValidateInterfaces < BaseValidator
      # For each composed interface, check the interface against each possible type
      # to assure that intersecting fields have compatible types, structures, and nullability.
      # Verifies compatibility of types that inherit interface contracts through merging.
      def perform(supergraph, composer)
        supergraph.schema.types.each do |type_name, interface_type|
          next unless interface_type.kind.interface?

          supergraph.schema.possible_types(interface_type).each do |possible_type|
            interface_type.fields.each do |field_name, interface_field|
              # graphql-ruby will dynamically apply interface fields on a type implementation,
              # so check the delegation map to assure that all materialized fields have resolver locations.
              unless supergraph.locations_by_type_and_field[possible_type.graphql_name][field_name]&.any?
                raise ValidationError, "Type #{possible_type.graphql_name} does not implement a `#{field_name}` field in any location, "\
                  "which is required by interface #{interface_type.graphql_name}."
              end

              intersecting_field = possible_type.fields[field_name]
              interface_type_structure = Util.flatten_type_structure(interface_field.type)
              possible_type_structure = Util.flatten_type_structure(intersecting_field.type)

              if possible_type_structure.length != interface_type_structure.length
                raise ValidationError, "Incompatible list structures between field #{possible_type.graphql_name}.#{field_name} of type "\
                  "#{intersecting_field.type.to_type_signature} and interface #{interface_type.graphql_name}.#{field_name} of type #{interface_field.type.to_type_signature}."
              end

              interface_type_structure.each_with_index do |interface_struct, index|
                possible_struct = possible_type_structure[index]

                if possible_struct.name != interface_struct.name
                  raise ValidationError, "Incompatible named types between field #{possible_type.graphql_name}.#{field_name} of type "\
                    "#{intersecting_field.type.to_type_signature} and interface #{interface_type.graphql_name}.#{field_name} of type #{interface_field.type.to_type_signature}."
                end

                if possible_struct.null? && interface_struct.non_null?
                  raise ValidationError, "Incompatible nullability between field #{possible_type.graphql_name}.#{field_name} of type "\
                    "#{intersecting_field.type.to_type_signature} and interface #{interface_type.graphql_name}.#{field_name} of type #{interface_field.type.to_type_signature}."
                end
              end
            end
          end
        end
      end

    end
  end
end
