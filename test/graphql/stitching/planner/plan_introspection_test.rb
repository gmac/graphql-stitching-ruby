# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"
require_relative "../../../schemas/introspection"

describe "GraphQL::Stitching::Planner, introspection" do
  def setup
    a = "type Apple { name: String } type Query { a:Apple }"
    b = "type Banana { name: String } type Query { b:Banana }"
    @supergraph = compose_definitions({ "a" => a, "b" => b })
  end

  def test_plans_full_introspection_query
    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      INTROSPECTION_QUERY,
      operation_name: "IntrospectionQuery",
    ).plan

    assert_equal 1, plan.ops.length
    assert_equal "__super", plan.ops.first.location
  end

  def test_stitches_introspection_with_other_locations
    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ __schema { queryType { name } } a { name } }|,
    ).plan

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      location: "__super",
      selections: %|{ __schema { queryType { name } } }|,
    }

    assert_keys plan.ops[1].as_json, {
      location: "a",
      selections: %|{ a { name } }|,
    }
  end

  def test_passes_through_typename_selections
    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ a { name __typename } }|,
    ).plan

    assert_equal 1, plan.ops.length

    assert_keys plan.ops.first.as_json, {
      location: "a",
      selections: %|{ a { name __typename } }|,
    }
  end

  def test_errors_for_reserved_selection_alias
    assert_error %|Alias "_export_name" is not allowed because "_export_" is a reserved prefix| do
      GraphQL::Stitching::Request.new(
        @supergraph,
        %|{ a { _export_name: name } }|,
      ).plan
    end
  end
end
