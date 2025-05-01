# frozen_string_literal: true

module GraphQL::Stitching
  class Supergraph
    module Visibility
      def visible?(ctx)
        profile = ctx[:visibility_profile]
        return true if profile.nil?

        directive = directives.find { _1.graphql_name == GraphQL::Stitching.visibility_directive }
        return true if directive.nil?

        profiles = directive.arguments.keyword_arguments[:profiles]
        return true if profiles.nil?

        profiles.include?(profile)
      end
    end
    
    class ArgumentType < GraphQL::Schema::Argument
      include Visibility
    end

    class FieldType < GraphQL::Schema::Field
      include Visibility
      argument_class(ArgumentType)
    end

    class InputObjectType < GraphQL::Schema::InputObject
      extend Visibility
      argument_class(ArgumentType)
    end

    module InterfaceType
      include GraphQL::Schema::Interface
      field_class(FieldType)

      definition_methods do
        include Visibility
      end
    end

    class ObjectType < GraphQL::Schema::Object
      extend Visibility
      field_class(FieldType)
    end

    class EnumValueType < GraphQL::Schema::EnumValue
      include Visibility
    end

    class EnumType < GraphQL::Schema::Enum
      extend Visibility
      enum_value_class(EnumValueType)
    end
    
    class ScalarType < GraphQL::Schema::Scalar
      extend Visibility
    end

    class UnionType < GraphQL::Schema::Union
      extend Visibility
    end

    BASE_TYPES = {
      enum: EnumType,
      input_object: InputObjectType,
      interface: InterfaceType,
      object: ObjectType,
      scalar: ScalarType,
      union: UnionType,
    }.freeze
  end
end
