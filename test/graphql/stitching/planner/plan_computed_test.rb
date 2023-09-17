# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, computed fields" do
  def setup
    a = %|
      type Product {
        id: ID!
        title: String!
        weight: Int!
      }
      type Query {
        products(ids: [ID!]!): [Product]! @stitch(key: "id")
      }
    |

    b = %|
      type Product {
        id: ID!
        shippingCost: Int! # @requires(fields: "weight")
      }
      type Query {
        productById(ids: ID!): Product! @stitch(key: "id")
      }
    |

    @supergraph = compose_definitions({ "a" => a, "b" => b })
    @supergraph.field_dependencies_by_type = {
      "Product" => {
        "shippingCost" => ["weight"],
      }
    }
  end

  def test_expands_interface_selections_for_target_location
    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new('{ products(ids: ["1"]) { title shippingCost } }'),
    ).perform

    pp plan.as_json
  end

  def test_expands_interface_selections_for_target_location
    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new('{ productById(id: "1") { title shippingCost } }'),
    ).perform

    pp plan.as_json
  end
end
