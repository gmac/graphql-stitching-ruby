# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"

describe "GraphQL::Stitching::Planner, introspection" do
  def setup
    @introspection = "
      query IntrospectionQuery {
        __schema {
          queryType { name }
          mutationType { name }
          types { ...FullType }
          directives {
            name
            description
            locations
            args { ...InputValue }
          }
        }
      }

      fragment FullType on __Type {
        kind
        name
        description
        fields(includeDeprecated: true) {
          name
          description
          args { ...InputValue }
          type { ...TypeRef }
          isDeprecated
          deprecationReason
        }
        inputFields { ...InputValue }
        interfaces { ...TypeRef }
        enumValues(includeDeprecated: true) {
          name
          description
          isDeprecated
          deprecationReason
        }
        possibleTypes { ...TypeRef }
      }

      fragment InputValue on __InputValue {
        name
        description
        type { ...TypeRef }
        defaultValue
      }

      fragment TypeRef on __Type {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                  ofType {
                    kind
                    name
                    ofType {
                      kind
                      name
                    }
                  }
                }
              }
            }
          }
        }
      }
    "
  end

  def test_plans_introspection_query
    a = "input Test { name: String } type Query { test:Test }"
    supergraph = compose_definitions({ "a" => a })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL.parse(@introspection),
      operation_name: "IntrospectionQuery",
    ).perform

    pp plan.as_json
  end
end
