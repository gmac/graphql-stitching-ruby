# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, boundaries" do
  def build_sample_graph
    @storefronts_sdl = %|
      type Storefront {
        id: ID!
        name: String!
        products: [Product]!
      }
      type Product {
        upc: ID!
      }
      type Query {
        storefront(id: ID!): Storefront
      }
    |

    @products_sdl = %|
      type Product {
        upc: ID!
        name: String!
        price: Float!
        manufacturer: Manufacturer!
      }
      type Manufacturer {
        id: ID!
        name: String!
        products: [Product]!
      }
      type Query {
        product(upc: ID!): Product @stitch(key: \"upc\")
        productsManufacturer(id: ID!): Manufacturer @stitch(key: \"id\")
      }
    |

    @manufacturers_sdl = %|
      type Manufacturer {
        id: ID!
        name: String!
        address: String!
      }
      type Query {
        manufacturer(id: ID!): Manufacturer @stitch(key: \"id\")
      }
    |

    compose_definitions({
      "storefronts" => @storefronts_sdl,
      "products" => @products_sdl,
      "manufacturers" => @manufacturers_sdl,
    })
  end

  def test_collects_unique_fields_across_boundary_locations
    document = %|
      query {
        storefront(id: "1") {
          name
          products {
            name
            manufacturer {
              address
              products {
                name
              }
            }
          }
        }
      }
    |

    plan = GraphQL::Stitching::Planner.new(
      supergraph: build_sample_graph,
      request: GraphQL::Stitching::Request.new(document),
    ).perform

    assert_equal 3, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "storefronts",
      operation_type: "query",
      selections: %|{ storefront(id: "1") { name products { _STITCH_upc: upc _STITCH___typename: __typename } } }|,
      path: [],
      boundary: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops[0].step,
      location: "products",
      operation_type: "query",
      selections: %|{ name manufacturer { products { name } _STITCH_id: id _STITCH___typename: __typename } }|,
      path: ["storefront", "products"],
      boundary: {
        field: "product",
        key: "upc",
      },
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops[1].step,
      location: "manufacturers",
      operation_type: "query",
      selections: %|{ address }|,
      path: ["storefront", "products", "manufacturer"],
      boundary: {
        field: "manufacturer",
        key: "id",
      },
    }
  end

  def test_collects_common_fields_from_first_available_location
    supergraph = build_sample_graph
    document1 = %|{         manufacturer(id: "1") { name products { name } } }|
    document2 = %|{ productsManufacturer(id: "1") { name products { name } } }|

    plan1 = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      request: GraphQL::Stitching::Request.new(document1),
    ).perform

    plan2 = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      request: GraphQL::Stitching::Request.new(document2),
    ).perform

    assert_equal 2, plan1.ops.length
    assert_equal 1, plan2.ops.length

    assert_keys plan1.ops[0].as_json, {
      after: 0,
      location: "manufacturers",
      operation_type: "query",
      selections: %|{ manufacturer(id: "1") { name _STITCH_id: id _STITCH___typename: __typename } }|,
      path: [],
      boundary: nil,
    }

    assert_keys plan1.ops[1].as_json, {
      after: plan1.ops.first.step,
      location: "products",
      operation_type: "query",
      selections: %|{ products { name } }|,
      path: ["manufacturer"],
      boundary: {
        field: "productsManufacturer",
        key: "id",
      },
    }

    assert_keys plan2.ops[0].as_json, {
      after: 0,
      location: "products",
      operation_type: "query",
      selections: %|{ productsManufacturer(id: "1") { name products { name } } }|,
      path: [],
      boundary: nil,
    }
  end

  def test_expands_selections_targeting_interface_locations
    a = %|
      type Apple { id:ID! name:String }
      type Query { apple(id:ID!):Apple @stitch(key:"id") }
    |

    b = %|
      interface Node { id:ID! }
      type Apple implements Node { id:ID! weight:Int }
      type Banana implements Node { id:ID! weight:Int }
      type Query { node(id:ID!):Node @stitch(key:"id") }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      request: GraphQL::Stitching::Request.new(%|{ apple(id:"1") { id name weight } }|),
    ).perform

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "a",
      operation_type: "query",
      selections: %|{ apple(id: "1") { id name _STITCH_id: id _STITCH___typename: __typename } }|,
      path: [],
      boundary: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "b",
      operation_type: "query",
      selections: %|{ ... on Apple { weight } }|,
      path: ["apple"],
      boundary: {
        field: "node",
        key: "id",
      },
    }
  end

  def test_expands_selections_targeting_union_locations
    a = %|
      type Apple { id:ID! name:String }
      type Query { apple(id:ID!):Apple @stitch(key:"id") }
    |

    b = %|
      type Apple { id:ID! weight:Int }
      type Banana { id:ID! weight:Int }
      union Node = Apple \| Banana
      type Query { node(id:ID!):Node @stitch(key:"id") }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      request: GraphQL::Stitching::Request.new("{ apple(id:\"1\") { id name weight } }"),
    ).perform

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "a",
      operation_type: "query",
      selections: %|{ apple(id: "1") { id name _STITCH_id: id _STITCH___typename: __typename } }|,
      path: [],
      boundary: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "b",
      operation_type: "query",
      selections: %|{ ... on Apple { weight } }|,
      path: ["apple"],
      boundary: {
        field: "node",
        key: "id",
      },
    }
  end

  def test_expands_selections_for_abstracts_targeting_abstract_locations
    a = %|
      interface Node { id:ID! }
      type Apple implements Node { id:ID! name:String }
      type Query { node(id:ID!):Node @stitch(key:"id") }
    |

    b = %|
      type Apple { id:ID! weight:Int }
      type Banana { id:ID! weight:Int }
      union Fruit = Apple \| Banana
      type Query { fruit(id:ID!):Fruit @stitch(key:"id") }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      request: GraphQL::Stitching::Request.new(%|{ node(id:"1") { id ...on Apple { name weight } } }|),
    ).perform

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "a",
      operation_type: "query",
      selections: %|{ node(id: "1") { id ... on Apple { name _STITCH_id: id _STITCH___typename: __typename } _STITCH___typename: __typename } }|,
      path: [],
      boundary: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "b",
      operation_type: "query",
      selections: %|{ ... on Apple { weight } }|,
      path: ["node"],
      boundary: {
        field: "fruit",
        key: "id",
      },
    }
  end
end
