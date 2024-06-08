# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Plan" do
  def setup
    @resolver = GraphQL::Stitching::Resolver.new(
      location: "products",
      field: "storefronts",
      arg: "ids",
      key: "id",
      list: true,
      type_name: "Storefront"
    )

    @op = GraphQL::Stitching::Plan::Op.new(
      step: 2,
      after: 1,
      location: "products",
      operation_type: "query",
      path: ["storefronts"],
      if_type: "Storefront",
      selections: "{ name(lang:$lang) }",
      variables: { "lang" => "String!" },
      resolver: @resolver.version,
    )

    @plan = GraphQL::Stitching::Plan.new(ops: [@op])

    @serialized = {
      "ops" => [{
        "step" => 2,
        "after" => 1,
        "location" => "products",
        "operation_type" => "query",
        "selections" => "{ name(lang:$lang) }",
        "variables" => {"lang" => "String!"},
        "path" => ["storefronts"],
        "if_type" => "Storefront",
        "resolver" => @resolver.version,
      }],
    }
  end

  def test_as_json_serializes_a_plan
    assert_equal @serialized, JSON.parse(@plan.as_json.to_json)
  end

  def test_from_json_deserialized_a_plan
    plan = GraphQL::Stitching::Plan.from_json(@serialized)
    assert_equal [@op], plan.ops
    assert_equal @resolver.version, plan.ops.first.resolver
  end
end
