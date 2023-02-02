# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, merged interfaces" do
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

  def test_expands_interface_selections_for_target_location
    supergraph = build_supergraph

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL.parse("{ buyable(id:\"1\") { id name price } }"),
    ).perform

    first = plan.operations[0]
    first_sel = "{ buyable(id: \"1\") { id ... on Product { _STITCH_id: id } ... on Bundle { name price } _STITCH_typename: __typename } }"
    assert_equal "b", first.location
    assert_equal [], first.insertion_path
    assert_equal first_sel, first.selection_set
    assert_nil first.boundary
    assert_nil first.after_key

    second = plan.operations[1]
    assert_equal "a", second.location
    assert_equal ["buyable"], second.insertion_path
    assert_equal "{ name price }", second.selection_set
    assert_equal "products", second.boundary["field"]
    assert_equal "id", second.boundary["selection"]
    # @todo needs a type condition!!
    assert_equal first.key, second.after_key
  end

  def test_retains_interface_selections_appropraite_to_the_location
    supergraph = build_supergraph

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL.parse("{ products(ids:[\"1\"]) { id name price } }"),
    ).perform

    first = plan.operations[0]
    assert_equal "a", first.location
    assert_equal [], first.insertion_path
    assert_equal "{ products(ids: [\"1\"]) { id name price } }", first.selection_set
    assert_nil first.boundary
    assert_nil first.after_key
  end
end
