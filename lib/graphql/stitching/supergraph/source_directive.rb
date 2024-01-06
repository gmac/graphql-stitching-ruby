# frozen_string_literal: true

module GraphQL::Stitching
  class Supergraph
    class SourceDirective < GraphQL::Schema::Directive
      graphql_name "source"
      locations FIELD_DEFINITION
      argument :location, String, required: true
      repeatable true
    end
  end
end
