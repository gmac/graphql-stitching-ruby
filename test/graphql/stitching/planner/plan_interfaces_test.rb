# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, extended interfaces" do
  def build_supergraph
    a = "
      interface Buyable {
        id: ID!
        name: String!
        price: Float!
      }
      type Product implements Buyable {
        id: ID!
        name: String!
        price: Float!
      }
      type Query {
        products(ids: [ID!]!): [Product]! @boundary(key:\"id\")
      }
    "
    b = "
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
    "
    compose_definitions({ "a" => a, "b" => b })
  end

  def test_expands_selections_for_abstracts_targeting_abstract_locations
    supergraph = build_supergraph

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL.parse("{ buyable(id:\"1\") { id name price }"),
    ).perform

    pp plan.to_h

    byebug

    first = plan.operations[0]
    assert_equal "a", first.location
    assert_equal [], first.insertion_path
    assert_equal "{ node(id: \"1\") { id ... on Apple { name _STITCH_id: id } _STITCH_typename: __typename } }", first.selection_set
    assert_nil first.boundary
    assert_nil first.after_key

    second = plan.operations[1]
    assert_equal "b", second.location
    assert_equal ["node"], second.insertion_path
    assert_equal "{ ... on Apple { weight } }", second.selection_set
    assert_equal "fruit", second.boundary["field"]
    assert_equal "id", second.boundary["selection"]
    assert_equal first.key, second.after_key
  end
end
