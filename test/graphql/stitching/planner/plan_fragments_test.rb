# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, fragments" do
  def setup
    a = <<~GRAPHQL
      interface Buyable {
        id: ID!
        name: String!
        price: Float!
      }
      type Product implements Buyable {
        id: ID!
        name: String!
        price: Float!
        salePrice: Float
      }
      type Query {
        products(ids: [ID!]!): [Product]! @boundary(key:\"id\")
      }
    GRAPHQL

    b = <<~GRAPHQL
      interface Buyable { id: ID! }
      type Product implements Buyable { id: ID! }
      type Bundle implements Buyable {
        id: ID!
        name: String!
        price: Float!
        products: [Product]!
      }
      type Query {
        buyable(id: ID!): Buyable @boundary(key:\"id\")
      }
    GRAPHQL

    @supergraph = compose_definitions({ "a" => a, "b" => b })
  end

  def test_plans_through_inline_fragments
    query = "
      query($id: ID!) {
        buyable(id: $id) {
          name
          ...on Product { salePrice }
          ...on Bundle { products { salePrice } }
        }
      }
    "

    _plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      document: GraphQL::Stitching::Document.new(query),
    ).perform.to_h

    # pp plan
    # @todo
  end

  def test_plans_through_fragment_spreads
    # @todo
  end
end