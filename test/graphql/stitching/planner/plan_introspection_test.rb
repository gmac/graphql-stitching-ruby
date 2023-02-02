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

  def test_plans_full_introspection_query
    a = "type Apple { name: String } type Query { a:Apple }"
    b = "type Banana { name: String } type Query { b:Banana }"
    supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL.parse(@introspection),
      operation_name: "IntrospectionQuery",
    ).perform

    assert_equal 1, plan.operations.length
    assert_equal "__super", plan.operations.first.location
  end

  def test_stitches_introspection_with_other_locations
    a = "type Apple { name: String } type Query { a:Apple }"
    b = "type Banana { name: String } type Query { b:Banana }"
    supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL.parse("{ __schema { queryType { name } } a { name } }"),
    ).perform

    assert_equal 2, plan.operations.length

    assert_equal "__super", plan.operations[0].location
    assert_equal "{ __schema { queryType { name } } }", plan.operations[0].selection_set

    assert_equal "a", plan.operations[1].location
    assert_equal "{ a { name } }", plan.operations[1].selection_set
  end
end
