# frozen_string_literal: true

module GraphQL::Stitching
  class Supergraph
    class KeyDirective < GraphQL::Schema::Directive
      graphql_name "key"
      locations OBJECT, INTERFACE, UNION
      argument :key, String, required: true
      argument :location, String, required: true
      repeatable true
    end
  end
end
