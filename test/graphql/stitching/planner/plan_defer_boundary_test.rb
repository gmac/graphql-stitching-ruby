# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/conditionals"

describe "GraphQL::Stitching::Planner, defer via boundary" do
  def setup
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
        product(upc: ID!): Product @stitch(key: "upc")
        productsManufacturer(id: ID!): Manufacturer @stitch(key: "id")
      }
    |

    @manufacturers_sdl = %|
      type Manufacturer {
        id: ID!
        name: String!
        address: String!
      }
      type Query {
        manufacturer(id: ID!): Manufacturer @stitch(key: "id")
      }
    |

    @supergraph = compose_definitions({
      "products" => @products_sdl,
      "manufacturers" => @manufacturers_sdl,
    })
  end

  def test_anonymous_local_defer
    plan = plan_query  %|
      query {
        product(upc: "1") {
          name
          ...@defer { price }
        }
      }
    |

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "products",
      operation_type: "query",
      path: [],
      selections: %|{ product(upc: "1") { name _STITCH___typename: __typename _STITCH_upc: upc } }|,
      defer_label: nil,
      boundary: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "products",
      operation_type: "query",
      path: ["product"],
      selections: %|{ price }|,
      defer_label: "_STITCH_defer",
      boundary: {
        field: "product",
        key: "upc",
      },
    }
  end

  def test_labeled_defer
    plan = plan_query  %|
      query {
        product(upc: "1") {
          name
          ...@defer(label: "lazy") { price }
        }
      }
    |

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      location: "products",
      operation_type: "query",
      path: [],
      selections: %|{ product(upc: "1") { name _STITCH___typename: __typename _STITCH_upc: upc } }|,
      defer_label: nil,
      boundary: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "products",
      operation_type: "query",
      path: ["product"],
      selections: %|{ price }|,
      defer_label: "lazy",
      boundary: {
        field: "product",
        key: "upc",
      },
    }
  end

  def test_with_deferred_local_and_remote_selections
    plan = plan_query  %|
      query {
        product(upc: "1") {
          manufacturer {
            name
            ...@defer(label: "lazy") {
              products { upc }
              address
            }
          }
        }
      }
    |

    assert_equal 3, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "products",
      operation_type: "query",
      path: [],
      selections: %|{ product(upc: "1") { manufacturer { name _STITCH___typename: __typename _STITCH_id: id } } }|,
      defer_label: nil,
      boundary: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops.first.step,
      location: "products",
      operation_type: "query",
      path: ["product", "manufacturer"],
      selections: %|{ products { upc } }|,
      defer_label: "lazy",
      boundary: {
        field: "productsManufacturer",
        key: "id",
      },
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops.first.step,
      location: "manufacturers",
      operation_type: "query",
      path: ["product", "manufacturer"],
      selections: %|{ address }|,
      defer_label: "lazy",
      boundary: {
        field: "manufacturer",
        key: "id",
      },
    }
  end

  def test_with_only_remote_deferred
    plan = plan_query  %|
      query {
        manufacturer(id: "1") {
          ...@defer(label: "lazy") {
            products { upc name }
          }
        }
      }
    |

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      step: 1,
      after: 0,
      location: "manufacturers",
      operation_type: "query",
      selections: %|{ manufacturer(id: "1") { _STITCH___typename: __typename _STITCH_id: id } }|,
      path: [],
    }

    assert_keys plan.ops[1].as_json, {
      step: 3,
      after: 1,
      location: "products",
      operation_type: "query",
      selections: %|{ products { upc name } }|,
      path: ["manufacturer"],
      defer_label: "lazy",
      boundary: {
        field: "productsManufacturer",
        key: "id",
      },
    }
  end

  def test_with_multiple_deferred
    plan = plan_query  %|
      query {
        manufacturer(id: "1") {
          name
          ...@defer(label: "a") {
            products { upc name }
          }
          ...@defer(label: "b") {
            address
          }
        }
      }
    |

    assert_equal 3, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "manufacturers",
      operation_type: "query",
      selections: %|{ manufacturer(id: "1") { name _STITCH___typename: __typename _STITCH_id: id } }|,
      path: [],
    }

    assert_keys plan.ops[1].as_json, {
      step: 3,
      after: plan.ops.first.step,
      location: "products",
      operation_type: "query",
      selections: %|{ products { upc name } }|,
      path: ["manufacturer"],
      defer_label: "a",
      boundary: {
        field: "productsManufacturer",
        key: "id",
      },
    }

    assert_keys plan.ops[2].as_json, {
      step: 4,
      after: plan.ops.first.step,
      location: "manufacturers",
      operation_type: "query",
      selections: %|{ address }|,
      path: ["manufacturer"],
      defer_label: "b",
      boundary: {
        field: "manufacturer",
        key: "id",
      },
    }
  end

  def test_with_nested_defers
    plan = plan_query  %|
      query {
        manufacturer(id: "1") {
          name
          ...@defer(label: "a") {
            products {
              upc
              name
              ...@defer(label: "b") {
                manufacturer {
                  name
                }
              }
            }
          }
        }
      }
    |

    assert_equal 3, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "manufacturers",
      operation_type: "query",
      selections: %|{ manufacturer(id: "1") { name _STITCH___typename: __typename _STITCH_id: id } }|,
      path: [],
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops[0].step,
      location: "products",
      operation_type: "query",
      selections: %|{ products { upc name _STITCH___typename: __typename _STITCH_upc: upc } }|,
      path: ["manufacturer"],
      defer_label: "a",
      boundary: {
        field: "productsManufacturer",
        key: "id",
      },
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops[1].step,
      location: "products",
      operation_type: "query",
      selections: %|{ manufacturer { name } }|,
      path: ["manufacturer", "products"],
      defer_label: "b",
      boundary: {
        field: "product",
        key: "upc",
      },
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
