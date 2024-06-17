# frozen_string_literal: true

module GraphQL::Stitching
  class Supergraph
    class ResolverDirective < GraphQL::Schema::Directive
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
  end
end
