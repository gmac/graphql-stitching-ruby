# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::GraphContext" do

  class DummySchema < GraphQL::Schema
    class Query < GraphQL::Schema::Object
      field :a, String, null: true
    end
    query Query
  end

  FIELDS_MAP = {
    "Manufacturer" => {
      "id" => ["manufacturers", "products"],
      "name" => ["manufacturers"],
      "address" => ["manufacturers"],
      "products" => ["products"],
    },
    "Product" => {
      "upc" => ["products", "storefronts"],
      "name" => ["products"],
      "price" => ["products"],
      "manufacturer" => ["products"],
    },
    "Storefront" => {
      "id" => ["storefronts"],
      "name" => ["storefronts"],
      "products" => ["storefronts"],
    },
    "Query" => {
      "manufacturer" => ["manufacturers"],
      "product" => ["products"],
      "storefront" => ["storefronts"],
    },
  }

  BOUNDARIES_MAP = {
    "Manufacturer" => [
      {
        "location" => "manufacturers",
        "selection" => "id",
        "field" => "manufacturer",
        "arg" => "id",
      },
    ],
    "Product" => [
      {
        "location" => "products",
        "selection" => "upc",
        "field" => "product",
        "arg" => "upc",
      },
    ],
    "Storefront" => [
      {
        "location" => "storefronts",
        "selection" => "id",
        "field" => "storefront",
        "arg" => "id",
      },
    ],
  }

  def test_fields_by_type_and_location
    context = GraphQL::Stitching::GraphContext.new(
      schema: DummySchema,
      fields: FIELDS_MAP,
      boundaries: BOUNDARIES_MAP,
    )

    mapping = context.fields_by_type_and_location
    assert_equal FIELDS_MAP.keys.sort, mapping.keys.sort
    assert_equal ["address", "id", "name"], mapping["Manufacturer"]["manufacturers"].sort
    assert_equal ["id", "products"], mapping["Manufacturer"]["products"].sort
  end

  def test_locations_by_type
    context = GraphQL::Stitching::GraphContext.new(
      schema: DummySchema,
      fields: FIELDS_MAP,
      boundaries: BOUNDARIES_MAP,
    )

    mapping = context.locations_by_type
    assert_equal FIELDS_MAP.keys.sort, mapping.keys.sort
    assert_equal ["manufacturers", "products"], mapping["Manufacturer"].sort
    assert_equal ["products", "storefronts"], mapping["Product"].sort
  end

  def test_add_client_and_get_client_default
    context = GraphQL::Stitching::GraphContext.new(
      schema: DummySchema,
      fields: FIELDS_MAP,
      boundaries: BOUNDARIES_MAP,
    )

    client = context.add_client { "success" }
    assert_equal client, context.get_client
    assert_equal "success", context.get_client.call
  end

  def test_add_client_and_get_client_with_location
    context = GraphQL::Stitching::GraphContext.new(
      schema: DummySchema,
      fields: FIELDS_MAP,
      boundaries: BOUNDARIES_MAP,
    )

    client1 = context.add_client("products") { 1 }
    client2 = context.add_client("manufacturers") { 2 }

    assert_equal client1, context.get_client("products")
    assert_equal client2, context.get_client("manufacturers")

    assert_equal 1, context.get_client("products").call
    assert_equal 2, context.get_client("manufacturers").call
  end

  def test_route_to_locations_connects_types_across_locations
    a = %{
      type T { upc:ID! }
      type Query { a(upc:ID!):T @boundary(key: "upc") }
    }
    b = %{
      type T { id:ID! upc:ID! }
      type Query {
        ba(upc:ID!):T @boundary(key: "upc")
        bc(id:ID!):T @boundary(key: "id")
      }
    }
    c = %{
      type T { id:ID! }
      type Query { c(id:ID!):T @boundary(key: "id") }
    }

    context = compose_definitions({ "a" => a, "b" => b, "c" => c })

    routes = context.route_to_locations("T", "a", ["b", "c"])
    assert_equal ["b"], routes["b"].map { _1["location"] }
    assert_equal ["b", "c"], routes["c"].map { _1["location"] }

    routes = context.route_to_locations("T", "b", ["a", "c"])
    assert_equal ["a"], routes["a"].map { _1["location"] }
    assert_equal ["c"], routes["c"].map { _1["location"] }

    routes = context.route_to_locations("T", "c", ["a", "b"])
    assert_equal ["b", "a"], routes["a"].map { _1["location"] }
    assert_equal ["b"], routes["b"].map { _1["location"] }
  end

  def test_route_to_locations_favors_longer_paths_through_necessary_locations
    a = %{
      type T { id:ID! }
      type Query { a(id:ID!):T @boundary(key: "id") }
    }
    b = %{
      type T { id:ID! upc:ID! }
      type Query {
        ba(id:ID!):T @boundary(key: "id")
        bc(upc:ID!):T @boundary(key: "upc")
      }
    }
    c = %{
      type T { upc:ID! gid:ID! }
      type Query {
        cb(upc:ID!):T @boundary(key: "upc")
        cd(gid:ID!):T @boundary(key: "gid")
      }
    }
    d = %{
      type T { gid:ID! code:ID! }
      type Query {
        dc(gid:ID!):T @boundary(key: "gid")
        de(code:ID!):T @boundary(key: "code")
      }
    }
    e = %{
      type T { code:ID! id:ID! }
      type Query {
        ed(code:ID!):T @boundary(key: "code")
        ea(id:ID!):T @boundary(key: "id")
      }
    }

    context = compose_definitions({ "a" => a, "b" => b, "c" => c, "d" => d, "e" => e })

    routes = context.route_to_locations("T", "a", ["b", "c", "d"])
    assert_equal ["b", "c", "d"], routes["d"].map { _1["location"] }
    assert routes.none? { |_key, path| path.any? { _1["location"] == "e" } }
  end

  def test_route_to_locations_returns_nil_for_unreachable_locations
    a = %{
      type T { upc:ID! }
      type Query { a(upc:ID!):T @boundary(key: "upc") }
    }
    b = %{
      type T { id:ID! }
      type Query { b(id:ID!):T @boundary(key: "id") }
    }
    c = %{
      type T { id:ID! }
      type Query { c(id:ID!):T @boundary(key: "id") }
    }

    context = compose_definitions({ "a" => a, "b" => b, "c" => c })

    routes = context.route_to_locations("T", "b", ["a", "c"])
    assert_equal ["c"], routes["c"].map { _1["location"] }
    assert_nil routes["a"]
  end
end