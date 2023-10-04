# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/conditionals"

describe "GraphQL::Stitching::Planner, defer via root" do
  def setup
    @products_sdl = %|
      type Product {
        upc: ID!
        name: String!
        manufacturer: Manufacturer!
      }
      type Manufacturer {
        id: ID!
        products: [Product]!
      }
      type Query {
        product(upc: ID!): Product @stitch(key: "upc")
        productsManufacturer(id: ID!): Manufacturer @stitch(key: "id")
      }
      type Mutation {
        createProduct(input: Boolean!): Product
        updateProduct(input: Boolean!): Product
      }
    |

    @manufacturers_sdl = %|
      type Manufacturer {
        id: ID!
        name: String!
      }
      type Query {
        manufacturer(id: ID!): Manufacturer @stitch(key: "id")
      }
      type Mutation {
        createManufacturer(input: Boolean!): Manufacturer
        updateManufacturer(input: Boolean!): Manufacturer
      }
    |

    @supergraph = compose_definitions({
      "products" => @products_sdl,
      "manufacturers" => @manufacturers_sdl,
    })
  end

  def test_defer_query
    plan = plan_query  %|
      query {
        product(upc: "1") { name }
        ...@defer {
          manufacturer(id: "1") { name }
        }
      }
    |

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "products",
      operation_type: "query",
      path: [],
      selections: %|{ product(upc: "1") { name } }|,
      defer_label: nil,
      boundary: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: 0,
      location: "manufacturers",
      operation_type: "query",
      path: [],
      selections: %|{ manufacturer(id: "1") { name } }|,
      defer_label: "_STITCH_defer",
      boundary: nil,
    }
  end

  def test_defer_multiple_queries
    plan = plan_query  %|
      query {
        a: product(upc: "1") { name }
        ...@defer {
          d: product(upc: "3") { name }
          e: manufacturer(id: "3") { name }
        }
        b: product(upc: "2") { name }
        c: manufacturer(id: "2") { name }
        ...@defer(label: "lazy") {
          f: product(upc: "4") { name }
        }
      }
    |

    assert_equal 5, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "products",
      operation_type: "query",
      path: [],
      selections: %|{ a: product(upc: "1") { name } b: product(upc: "2") { name } }|,
      defer_label: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: 0,
      location: "manufacturers",
      operation_type: "query",
      path: [],
      selections: %|{ c: manufacturer(id: "2") { name } }|,
      defer_label: nil,
    }

    assert_keys plan.ops[2].as_json, {
      after: 0,
      location: "products",
      operation_type: "query",
      path: [],
      selections: %|{ d: product(upc: "3") { name } }|,
      defer_label: "_STITCH_defer",
    }

    assert_keys plan.ops[3].as_json, {
      after: 0,
      location: "manufacturers",
      operation_type: "query",
      path: [],
      selections: %|{ e: manufacturer(id: "3") { name } }|,
      defer_label: "_STITCH_defer",
    }

    assert_keys plan.ops[4].as_json, {
      after: 0,
      location: "products",
      operation_type: "query",
      path: [],
      selections: %|{ f: product(upc: "4") { name } }|,
      defer_label: "lazy",
    }
  end

  def test_defer_nested_queries
    plan = plan_query  %|
      query {
        product(upc: "1") { name }
        ...@defer(label: "a") {
          manufacturer(id: "2") {
            name
            ...@defer(label: "b") {
              products { name }
            }
          }
        }
      }
    |
    pp plan.as_json
    assert_equal 3, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "products",
      operation_type: "query",
      path: [],
      selections: %|{ product(upc: "1") { name } }|,
      defer_label: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: 0,
      location: "manufacturers",
      operation_type: "query",
      path: [],
      selections: %|{ manufacturer(id: "2") { name _STITCH___typename: __typename _STITCH_id: id } }|,
      defer_label: "a",
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops[1].step,
      location: "products",
      operation_type: "query",
      path: ["manufacturer"],
      selections: %|{ products { name } }|,
      defer_label: "b",
      boundary: {
        field: "productsManufacturer",
        key: "id",
      },
    }
  end

  def test_defer_root_mutations
    plan = plan_query  %|
      mutation {
        a: createProduct(input: true) { name }
        ...@defer {
          d: createProduct(input: true) { name }
          e: createProduct(input: true) { name }
          f: createManufacturer(input: true) { name }
        }
        b: createProduct(input: true) { name }
        c: createManufacturer(input: true) { name }
        ...@defer(label: "lazy") {
          g: createProduct(input: true) { name }
        }
      }
    |

    assert_equal 5, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "products",
      operation_type: "mutation",
      path: [],
      selections: %|{ a: createProduct(input: true) { name } b: createProduct(input: true) { name } }|,
      defer_label: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops[0].step,
      location: "manufacturers",
      operation_type: "mutation",
      path: [],
      selections: %|{ c: createManufacturer(input: true) { name } }|,
      defer_label: nil,
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops[1].step,
      location: "products",
      operation_type: "mutation",
      path: [],
      selections: %|{ d: createProduct(input: true) { name } e: createProduct(input: true) { name } }|,
      defer_label: "_STITCH_defer",
    }

    assert_keys plan.ops[3].as_json, {
      after: plan.ops[2].step,
      location: "manufacturers",
      operation_type: "mutation",
      path: [],
      selections: %|{ f: createManufacturer(input: true) { name } }|,
      defer_label: "_STITCH_defer",
    }

    assert_keys plan.ops[4].as_json, {
      after: plan.ops[3].step,
      location: "products",
      operation_type: "mutation",
      path: [],
      selections: %|{ g: createProduct(input: true) { name } }|,
      defer_label: "lazy",
    }
  end

  def test_defer_in_mutation_field_does_not_block_next_mutation
    plan = plan_query  %|
      mutation {
        a: createProduct(input: true) {
          ...@defer(label: "lazy") { name }
        }
        b: createManufacturer(input: true) { name }
      }
    |

    assert_equal 3, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "products",
      operation_type: "mutation",
      path: [],
      selections: %|{ a: createProduct(input: true) { _STITCH___typename: __typename _STITCH_upc: upc } }|,
      defer_label: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.last.step, # << follows last mutation
      location: "products",
      operation_type: "query",
      path: ["a"],
      selections: %|{ name }|,
      defer_label: "lazy",
      boundary: {
        field: "product",
        key: "upc",
      },
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops[0].step,
      location: "manufacturers",
      operation_type: "mutation",
      path: [],
      selections: %|{ b: createManufacturer(input: true) { name } }|,
      defer_label: nil,
    }
  end

  def test_defer_in_mutation_field_only_resequences_root_defer_steps
    plan = plan_query  %|
      mutation {
        a: createManufacturer(input: true) {
          ...@defer(label: "lazy1") {
            name
            products {
              manufacturer { name }
            }
          }
          ...@defer(label: "lazy2") {
            name
          }
        }
        b: createProduct(input: true) { name }
      }
    |

    assert_equal 6, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "manufacturers",
      operation_type: "mutation",
      path: [],
      selections: %|{ a: createManufacturer(input: true) { _STITCH___typename: __typename _STITCH_id: id } }|,
      defer_label: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.last.step, # << follows last mutation
      location: "manufacturers",
      operation_type: "query",
      path: ["a"],
      selections: %|{ name }|,
      defer_label: "lazy1",
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops.last.step, # << follows last mutation
      location: "products",
      operation_type: "query",
      path: ["a"],
      selections: %|{ products { manufacturer { _STITCH_id: id _STITCH___typename: __typename } } }|,
      defer_label: "lazy1",
    }

    assert_keys plan.ops[3].as_json, {
      after: plan.ops[2].step,
      location: "manufacturers",
      operation_type: "query",
      path: ["a", "products", "manufacturer"],
      selections: %|{ name }|,
      defer_label: nil,
    }

    assert_keys plan.ops[4].as_json, {
      after: plan.ops.last.step, # << follows last mutation
      location: "manufacturers",
      operation_type: "query",
      path: ["a"],
      selections: %|{ name }|,
      defer_label: "lazy2",
    }

    assert_keys plan.ops[5].as_json, {
      after: plan.ops[0].step,
      location: "products",
      operation_type: "mutation",
      path: [],
      selections: %|{ b: createProduct(input: true) { name } }|,
      defer_label: nil,
    }
  end

  private

  def plan_query(query)
    GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(query),
    ).perform
  end
end
