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
    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ buyable(id:"1") { id name price } }|,
    ).plan

    expected_root_selection = %|
      {
        buyable(id: "1") {
          id
          ... on Product {
            _export_id: id
            _export___typename: __typename
          }
          ... on Bundle {
            name
            price
          }
          _export___typename: __typename
        }
      }
    |

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "b",
      selections: squish_string(expected_root_selection),
      path: [],
      if_type: nil,
      resolver: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "a",
      selections: "{ name price }",
      path: ["buyable"],
      if_type: "Product",
      resolver: resolver_version("Product", {
        location: "a",
        field: "products",
        key: "id",
      }),
    }
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
            _export_id: id
            _export___typename: __typename
          }
          ... on Bundle {
            name
            price
          }
          _export___typename: __typename
        }
      }
    |

    [document1, document2, document3].each do |document|
      plan = GraphQL::Stitching::Request.new(@supergraph, document).plan

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
          ... on Product { _export_id: id _export___typename: __typename }
          ... on Bundle { name price }
          _export___typename: __typename
        }
      }
    |

    plan = GraphQL::Stitching::Request.new(@supergraph, document).plan

    assert_equal 2, plan.ops.length
    assert_equal squish_string(expected_root_selection), plan.ops.first.selections
  end

  def test_retains_interface_selections_appropraite_to_the_location
    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ products(ids:["1"]) { id name price } }|,
    ).plan

    assert_equal 1, plan.ops.length
    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "a",
      selections: %|{ products(ids: ["1"]) { id name price } }|,
      path: [],
      resolver: nil,
    }
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

    plan = GraphQL::Stitching::Request.new(@supergraph, document).plan

    expected_root_selection = %|
      {
        fruit {
          ... on Apple {
            a
            _export_id: id
            _export___typename: __typename
          }
          ... on Banana {
            a
            _export_id: id
            _export___typename: __typename
          }
          _export___typename: __typename
        }
      }
    |

    assert_equal 4, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "a",
      selections: squish_string(expected_root_selection),
      path: [],
      resolver: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "b",
      selections: "{ b }",
      path: ["fruit"],
      if_type: "Apple",
      resolver: resolver_version("Apple", {
        location: "b",
        key: "id",
      }),
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops.first.step,
      location: "c",
      selections: "{ c }",
      path: ["fruit"],
      if_type: "Apple",
      resolver: resolver_version("Apple", {
        location: "c",
        key: "id",
      }),
    }

    assert_keys plan.ops[3].as_json, {
      after: plan.ops.first.step,
      location: "b",
      selections: "{ b }",
      path: ["fruit"],
      if_type: "Banana",
      resolver: resolver_version("Banana", {
        location: "b",
        key: "id",
      }),
    }
  end

  private

  def resolver_version(type_name, criteria)
    @supergraph.resolvers[type_name].find do |resolver|
      json = resolver.as_json
      criteria.all? { |k, v| json[k] == v }
    end.version
  end
end
