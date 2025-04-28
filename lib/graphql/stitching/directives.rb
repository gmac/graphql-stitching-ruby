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
  end
end
