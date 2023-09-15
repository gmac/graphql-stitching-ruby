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

    first = plan.ops[0]
    assert_equal "storefronts", first.location
    assert_equal "query", first.operation_type
    assert_equal [], first.path
    assert_equal %|{ storefront(id: "1") { name products { _STITCH_upc: upc _STITCH_typename: __typename } } }|, first.selections
    assert_equal 1, first.step
    assert_equal 0, first.after
    assert_nil first.boundary

    second = plan.ops[1]
    assert_equal "products", second.location
    assert_equal "query", second.operation_type
    assert_equal ["storefront", "products"], second.path
    assert_equal "{ name manufacturer { products { name } _STITCH_id: id _STITCH_typename: __typename } }", second.selections
    assert_equal "product", second.boundary.field
    assert_equal "upc", second.boundary.key
    assert_equal first.step, second.after

    third = plan.ops[2]
    assert_equal "manufacturers", third.location
    assert_equal "query", third.operation_type
    assert_equal ["storefront", "products", "manufacturer"], third.path
    assert_equal "{ address }", third.selections
    assert_equal "manufacturer", third.boundary.field
    assert_equal "id", third.boundary.key
    assert_equal second.step, third.after
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

    p1_first = plan1.ops[0]
    assert_equal "manufacturers", p1_first.location
    assert_equal "query", p1_first.operation_type
    assert_equal [], p1_first.path
    assert_equal %|{ manufacturer(id: "1") { name _STITCH_id: id _STITCH_typename: __typename } }|, p1_first.selections
    assert_equal 1, p1_first.step
    assert_equal 0, p1_first.after
    assert_nil p1_first.boundary

    p1_second = plan1.ops[1]
    assert_equal "products", p1_second.location
    assert_equal "query", p1_second.operation_type
    assert_equal ["manufacturer"], p1_second.path
    assert_equal "{ products { name } }", p1_second.selections
    assert_equal p1_first.step, p1_second.after
    assert_equal "productsManufacturer", p1_second.boundary.field
    assert_equal "id", p1_second.boundary.key

    p2_first = plan2.ops[0]
    assert_equal "products", p2_first.location
    assert_equal "query", p2_first.operation_type
    assert_equal [], p2_first.path
    assert_equal %|{ productsManufacturer(id: "1") { name products { name } } }|, p2_first.selections
    assert_equal 1, p2_first.step
    assert_equal 0, p2_first.after
    assert_nil p2_first.boundary
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

    first = plan.ops[0]
    assert_equal "a", first.location
    assert_equal [], first.path
    assert_equal %|{ apple(id: "1") { id name _STITCH_id: id _STITCH_typename: __typename } }|, first.selections
    assert_equal 1, first.step
    assert_equal 0, first.after
    assert_nil first.boundary

    second = plan.ops[1]
    assert_equal "b", second.location
    assert_equal ["apple"], second.path
    assert_equal "{ ... on Apple { weight } }", second.selections
    assert_equal "node", second.boundary.field
    assert_equal "id", second.boundary.key
    assert_equal first.step, second.after
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

    first = plan.ops[0]
    assert_equal "a", first.location
    assert_equal [], first.path
    assert_equal %|{ apple(id: "1") { id name _STITCH_id: id _STITCH_typename: __typename } }|, first.selections
    assert_equal 1, first.step
    assert_equal 0, first.after
    assert_nil first.boundary

    second = plan.ops[1]
    assert_equal "b", second.location
    assert_equal ["apple"], second.path
    assert_equal "{ ... on Apple { weight } }", second.selections
    assert_equal "node", second.boundary.field
    assert_equal "id", second.boundary.key
    assert_equal first.step, second.after
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

    first = plan.ops[0]
    assert_equal "a", first.location
    assert_equal [], first.path
    assert_equal %|{ node(id: "1") { id ... on Apple { name _STITCH_id: id _STITCH_typename: __typename } _STITCH_typename: __typename } }|, first.selections
    assert_equal 1, first.step
    assert_equal 0, first.after
    assert_nil first.boundary

    second = plan.ops[1]
    assert_equal "b", second.location
    assert_equal ["node"], second.path
    assert_equal "{ ... on Apple { weight } }", second.selections
    assert_equal "fruit", second.boundary.field
    assert_equal "id", second.boundary.key
    assert_equal first.step, second.after
  end
end
