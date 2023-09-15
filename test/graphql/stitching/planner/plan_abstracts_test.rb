# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, abstract merged types" do
  def setup
    a = %|
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
        products(ids: [ID!]!): [Product]! @stitch(key: "id")
      }
    |

    b = %|
      interface Buyable { id: ID! }
      type Product implements Buyable { id: ID! }
      type Bundle implements Buyable {
        id: ID!
        name: String!
        price: Float!
        products: [Product]!
      }
      type Query {
        buyable(id: ID!): Buyable @stitch(key: "id")
      }
    |

    @supergraph = compose_definitions({ "a" => a, "b" => b })
  end

  def test_expands_interface_selections_for_target_location
    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new("{ buyable(id:\"1\") { id name price } }"),
    ).perform

    expected_root_selection = %|
      {
        buyable(id: "1") {
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
    |

    assert_equal 2, plan.ops.length

    first = plan.ops[0]
    assert_equal "b", first.location
    assert_equal [], first.path
    assert_equal squish_string(expected_root_selection), first.selections
    assert_equal 0, first.after
    assert_nil first.if_type
    assert_nil first.boundary

    second = plan.ops[1]
    assert_equal "a", second.location
    assert_equal ["buyable"], second.path
    assert_equal "{ name price }", second.selections
    assert_equal "products", second.boundary["field"]
    assert_equal "id", second.boundary["key"]
    assert_equal "Product", second.if_type
    assert_equal first.step, second.after
  end

  def test_expands_interface_selection_fragments
    document1 = %|
      {
        buyable(id: "1") {
          ...on Buyable { id name price }
        }
      }
    |

    document2 = %|
      {
        buyable(id: "1") {
          ... { id name price }
        }
      }
    |

    document3 = %|
      {
        buyable(id: "1") {
          ...BuyableAttrs
        }
      }
      fragment BuyableAttrs on Buyable { id name price }
    |

    expected_root_selection = %|
      {
        buyable(id: "1") {
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
          _STITCH_typename: __typename
        }
      }
    |

    [document1, document2, document3].each do |document|
      plan = GraphQL::Stitching::Planner.new(
        supergraph: @supergraph,
        request: GraphQL::Stitching::Request.new(document),
      ).perform

      assert_equal 2, plan.ops.length
      assert_equal squish_string(expected_root_selection), plan.ops.first.selections
    end
  end

  def test_expands_nested_interface_selection_fragments
    document = %|
      {
        buyable(id: "1") {
          ... {
            ...BuyableAttrs
          }
        }
      }
      fragment BuyableAttrs on Buyable { id name price }
    |

    expected_root_selection = %|
      {
        buyable(id: \"1\") {
          id
          ... on Product { _STITCH_id: id _STITCH_typename: __typename }
          ... on Bundle { name price }
          _STITCH_typename: __typename
          _STITCH_typename: __typename
          _STITCH_typename: __typename
        }
      }
    |

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(document),
    ).perform

    assert_equal 2, plan.ops.length
    assert_equal squish_string(expected_root_selection), plan.ops.first.selections
  end

  def test_retains_interface_selections_appropraite_to_the_location
    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new("{ products(ids:[\"1\"]) { id name price } }"),
    ).perform

    first = plan.ops[0]
    assert_equal "a", first.location
    assert_equal [], first.path
    assert_equal "{ products(ids: [\"1\"]) { id name price } }", first.selections
    assert_equal 0, first.after
    assert_nil first.boundary
  end

  def test_plan_merged_union_types
    a = %|
      type Apple { id: ID! a: String }
      type Banana { id: ID! a: String }
      union Fruit = Apple \| Banana
      type Query {
        fruit: Fruit
        apple(id: ID!): Apple @stitch(key: "id")
        banana(id: ID!): Banana @stitch(key: "id")
      }
    |

    b = %|
      type Apple { id: ID! b: String }
      type Banana { id: ID! b: String }
      type Query {
        apple(id: ID!): Apple @stitch(key: "id")
        banana(id: ID!): Banana @stitch(key: "id")
      }
    |

    c = %|
      type Apple { id: ID! c: String }
      type Coconut { id: ID! c: String }
      union Fruit = Apple \| Coconut
      type Query {
        apple(id: ID!): Apple @stitch(key: "id")
        coconut(id: ID!): Coconut @stitch(key: "id")
      }
    |

    document = %|
      {
        fruit {
          ...on Apple { a b c }
          ...on Banana { a b }
          ...on Coconut { c }
        }
      }
    |

    @supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(document),
    ).perform

    assert_equal 4, plan.ops.length

    expected_root_selection = %|
      {
        fruit {
          ... on Apple {
            a
            _STITCH_id: id
            _STITCH_typename: __typename
          }
          ... on Banana {
            a
            _STITCH_id: id
            _STITCH_typename: __typename
          }
          _STITCH_typename: __typename
        }
      }
    |

    first = plan.ops[0]
    assert_equal "a", first.location
    assert_equal [], first.path
    assert_equal squish_string(expected_root_selection), first.selections

    second = plan.ops[1]
    assert_equal "b", second.location
    assert_equal "Apple", second.if_type
    assert_equal ["fruit"], second.path
    assert_equal "{ b }", second.selections

    third = plan.ops[2]
    assert_equal "c", third.location
    assert_equal "Apple", third.if_type
    assert_equal ["fruit"], third.path
    assert_equal "{ c }", third.selections

    fourth = plan.ops[3]
    assert_equal "b", fourth.location
    assert_equal "Banana", fourth.if_type
    assert_equal ["fruit"], fourth.path
    assert_equal "{ b }", fourth.selections
  end
end
