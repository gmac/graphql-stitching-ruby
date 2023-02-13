# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"
require_relative "../../../schemas/introspection"

describe "GraphQL::Stitching::Planner, introspection" do
  def test_plans_full_introspection_query
    a = "type Apple { name: String } type Query { a:Apple }"
    b = "type Banana { name: String } type Query { b:Banana }"
    supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      request: GraphQL::Stitching::Request.new(INTROSPECTION_QUERY, operation_name: "IntrospectionQuery"),
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
      request: GraphQL::Stitching::Request.new("{ __schema { queryType { name } } a { name } }"),
    ).perform

    assert_equal 2, plan.operations.length

    assert_equal "__super", plan.operations[0].location
    assert_equal "{ __schema { queryType { name } } }", plan.operations[0].selection_set

    assert_equal "a", plan.operations[1].location
    assert_equal "{ a { name } }", plan.operations[1].selection_set
  end
end
