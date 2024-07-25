# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, resolvers" do
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

    @supergraph = compose_definitions({
      "storefronts" => @storefronts_sdl,
      "products" => @products_sdl,
      "manufacturers" => @manufacturers_sdl,
    })
  end

  def test_collects_unique_fields_across_resolver_locations
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

    plan = GraphQL::Stitching::Request.new(build_sample_graph, document).plan

    assert_equal 3, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "storefronts",
      operation_type: "query",
      selections: %|{ storefront(id: "1") { name products { _export_upc: upc _export___typename: __typename } } }|,
      path: [],
      resolver: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops[0].step,
      location: "products",
      operation_type: "query",
      selections: %|{ name manufacturer { products { name } _export_id: id _export___typename: __typename } }|,
      path: ["storefront", "products"],
      resolver: resolver_version("Product", {
        location: "products",
        field: "product",
        key: "upc",
      }),
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops[1].step,
      location: "manufacturers",
      operation_type: "query",
      selections: %|{ address }|,
      path: ["storefront", "products", "manufacturer"],
      resolver: resolver_version("Manufacturer", {
        location: "manufacturers",
        field: "manufacturer",
        key: "id",
      }),
    }
  end

  def test_collects_common_fields_from_first_available_location
    supergraph = build_sample_graph
    document1 = %|{         manufacturer(id: "1") { name products { name } } }|
    document2 = %|{ productsManufacturer(id: "1") { name products { name } } }|

    plan1 = GraphQL::Stitching::Request.new(supergraph, document1).plan
    plan2 = GraphQL::Stitching::Request.new(supergraph, document2).plan

    assert_equal 2, plan1.ops.length
    assert_equal 1, plan2.ops.length

    assert_keys plan1.ops[0].as_json, {
      after: 0,
      location: "manufacturers",
      operation_type: "query",
      selections: %|{ manufacturer(id: "1") { name _export_id: id _export___typename: __typename } }|,
      path: [],
      resolver: nil,
    }

    assert_keys plan1.ops[1].as_json, {
      after: plan1.ops.first.step,
      location: "products",
      operation_type: "query",
      selections: %|{ products { name } }|,
      path: ["manufacturer"],
      resolver: resolver_version("Manufacturer", {
        location: "products",
        field: "productsManufacturer",
        key: "id",
      }),
    }

    assert_keys plan2.ops[0].as_json, {
      after: 0,
      location: "products",
      operation_type: "query",
      selections: %|{ productsManufacturer(id: "1") { name products { name } } }|,
      path: [],
      resolver: nil,
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

    @supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ apple(id:"1") { id name weight } }|,
    ).plan

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "a",
      operation_type: "query",
      selections: %|{ apple(id: "1") { id name _export_id: id _export___typename: __typename } }|,
      path: [],
      resolver: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "b",
      operation_type: "query",
      selections: %|{ ... on Apple { weight } }|,
      path: ["apple"],
      resolver: resolver_version("Apple", {
        location: "b",
        field: "node",
        key: "id",
      }),
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

    @supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ apple(id:"1") { id name weight } }|,
    ).plan

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "a",
      operation_type: "query",
      selections: %|{ apple(id: "1") { id name _export_id: id _export___typename: __typename } }|,
      path: [],
      resolver: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "b",
      operation_type: "query",
      selections: %|{ ... on Apple { weight } }|,
      path: ["apple"],
      resolver: resolver_version("Apple", {
        location: "b",
        field: "node",
        key: "id",
      }),
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

    @supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ node(id:"1") { id ...on Apple { name weight } } }|,
    ).plan

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "a",
      operation_type: "query",
      selections: %|{ node(id: "1") { id ... on Apple { name _export_id: id _export___typename: __typename } _export___typename: __typename } }|,
      path: [],
      resolver: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "b",
      operation_type: "query",
      selections: %|{ ... on Apple { weight } }|,
      path: ["node"],
      resolver: resolver_version("Apple", {
        location: "b",
        field: "fruit",
        key: "id",
      }),
    }
  end

  def test_plans_subscription_resolvers
    a = %|
      type Apple { id:ID! flavor:String }
      type Query { appleA(id:ID!):Apple @stitch(key:"id") }
      type Subscription { watchApple: Apple }
    |

    b = %|
      type Apple { id:ID! color:String }
      type Query { appleB(id:ID!):Apple @stitch(key:"id") }
    |

    @supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      %|subscription { watchApple { id flavor color } }|,
    ).plan

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "a",
      operation_type: "subscription",
      selections: %|{ watchApple { id flavor _export_id: id _export___typename: __typename } }|,
      path: [],
      resolver: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "b",
      operation_type: "query",
      selections: %|{ color }|,
      path: ["watchApple"],
      resolver: resolver_version("Apple", {
        location: "b",
        field: "appleB",
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
