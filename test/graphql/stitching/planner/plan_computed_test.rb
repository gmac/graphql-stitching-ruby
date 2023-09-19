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
        size: Int!
      }
      type Query {
        productById(ids: ID!): Product! @stitch(key: "id")
      }
    |

    @supergraph = compose_definitions({ "a" => a, "b" => b })
    @supergraph.field_dependencies_by_type = {
      "Product" => {
        "shippingCost" => ["weight"],
        "weight" => ["size"],
      }
    }
  end

  def test_plans_computed_fields1
    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new('{ products(ids: ["1"]) { title shippingCost } }'),
    ).perform

    pp plan.as_json
  end

  # def test_plans_computed_fields2
  #   plan = GraphQL::Stitching::Planner.new(
  #     supergraph: @supergraph,
  #     request: GraphQL::Stitching::Request.new('{ productById(id: "1") { title shippingCost } }'),
  #   ).perform

  #   pp plan.as_json
  # end
end
