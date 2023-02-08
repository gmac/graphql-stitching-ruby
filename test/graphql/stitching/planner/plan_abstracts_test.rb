# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, abstract merged types" do
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
        products(ids: [ID!]!): [Product]! @stitch(key:\"id\")
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
        buyable(id: ID!): Buyable @stitch(key:\"id\")
      }
    "
    compose_definitions({ "a" => a, "b" => b })
  end

  def test_expands_interface_selections_for_target_location
    supergraph = build_supergraph

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL::Stitching::Document.new("{ buyable(id:\"1\") { id name price } }"),
    ).perform

    expected_root_selection = <<~GRAPHQL
      {
        buyable(id: \"1\") {
          id
          ... on Product {
            _STITCH_id: id
            _STITCH_typename: __typename
          }
          ... on Bundle {
            name
            price
          }
          _STITCH_typename: __typename
        }
      }
    GRAPHQL

    first = plan.operations[0]
    assert_equal "b", first.location
    assert_equal [], first.insertion_path
    assert_equal expected_root_selection.gsub(/\s+/, " ").strip!, first.selection_set
    assert_equal 0, first.after_key
    assert_nil first.type_condition
    assert_nil first.boundary

    second = plan.operations[1]
    assert_equal "a", second.location
    assert_equal ["buyable"], second.insertion_path
    assert_equal "{ name price }", second.selection_set
    assert_equal "products", second.boundary["field"]
    assert_equal "id", second.boundary["selection"]
    assert_equal "Product", second.type_condition
    assert_equal first.key, second.after_key
  end

  def test_retains_interface_selections_appropraite_to_the_location
    supergraph = build_supergraph

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL::Stitching::Document.new("{ products(ids:[\"1\"]) { id name price } }"),
    ).perform

    first = plan.operations[0]
    assert_equal "a", first.location
    assert_equal [], first.insertion_path
    assert_equal "{ products(ids: [\"1\"]) { id name price } }", first.selection_set
    assert_equal 0, first.after_key
    assert_nil first.boundary
  end

  # def test_plan_abstract_merged_types
  #   a = "
  #     type Apple { id: ID! a: String }
  #     type Banana { id: ID! a: String }
  #     union Fruit = Apple | Banana
  #     type Query {
  #       fruit: Fruit
  #       apple(id: ID!): Apple @stitch(key: \"id\")
  #       banana(id: ID!): Banana @stitch(key: \"id\")
  #     }
  #   "
  #   b = "
  #     type Apple { id: ID! b: String }
  #     type Banana { id: ID! b: String }
  #     type Query {
  #       apple(id: ID!): Apple @stitch(key: \"id\")
  #       banana(id: ID!): Banana @stitch(key: \"id\")
  #     }
  #   "
  #   c = "
  #     type Apple { id: ID! c: String }
  #     type Coconut { id: ID! c: String }
  #     union Fruit = Apple | Coconut
  #     type Query {
  #       apple(id: ID!): Apple @stitch(key: \"id\")
  #       coconut(id: ID!): Coconut @stitch(key: \"id\")
  #     }
  #   "

  #   query = "{ fruit { ...on Apple { a b c } ...on Banana { a b } ...on Coconut { c } } }"

  #   supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c })
  #   plan = GraphQL::Stitching::Planner.new(
  #     supergraph: supergraph,
  #     document: GraphQL::Stitching::Document.new(query),
  #   ).perform

  #   pp plan.to_h
  # end
end
