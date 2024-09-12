class StitchingResolver < GraphQL::Schema::Directive
  graphql_name "stitch"
  locations FIELD_DEFINITION
  argument :key, String, required: true
  argument :arguments, String, required: false
  repeatable true
end
