# frozen_string_literal: true

module GraphQL::Stitching
  module Directives
    class Stitch < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String, required: true
      argument :arguments, String, required: false
      argument :type_name, String, required: false
      repeatable true
    end

    class Visibility < GraphQL::Schema::Directive
      graphql_name "visibility"
      locations(
        OBJECT, INTERFACE, UNION, INPUT_OBJECT, ENUM, SCALAR, 
        FIELD_DEFINITION, ARGUMENT_DEFINITION, INPUT_FIELD_DEFINITION, ENUM_VALUE
      )
      argument :profiles, [String, null: false], required: true
    end

    class SupergraphKey < GraphQL::Schema::Directive
      graphql_name "key"
      locations OBJECT, INTERFACE, UNION
      argument :key, String, required: true
      argument :location, String, required: true
      repeatable true
    end

    class SupergraphResolver < GraphQL::Schema::Directive
      graphql_name "resolver"
      locations OBJECT, INTERFACE, UNION
      argument :location, String, required: true
      argument :list, Boolean, required: false
      argument :key, String, required: true
      argument :field, String, required: true
      argument :arguments, String, required: true
      argument :argument_types, String, required: true
      argument :type_name, String, required: false
      repeatable true
    end
    
    class SupergraphSource < GraphQL::Schema::Directive
      graphql_name "source"
      locations FIELD_DEFINITION
      argument :location, String, required: true
      repeatable true
    end
  end
end
