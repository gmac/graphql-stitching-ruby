# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/example"

describe "GraphQL::Stitching::Supergraph" do

  class ComposedSchema < GraphQL::Schema
    class Product < GraphQL::Schema::Object
      # products, storefronts
      field :upc, ID, null: false
      # products
      field :name, String, null: false
      # products
      field :price, Int, null: false
      # products
      field :manufacturer, "ComposedSchema::Manufacturer", null: false
    end

    class Manufacturer < GraphQL::Schema::Object
      # products, manufacturers
      field :id, ID, null: false
      # manufacturers
      field :name, String, null: false
      # manufacturers
      field :address, String, null: false
      # products
      field :products, [Product], null: false
    end

    class Storefront < GraphQL::Schema::Object
      # storefronts
      field :id, ID, null: false
      # storefronts
      field :name, String, null: false
      # storefronts
      field :products, [Product], null: false
    end

    class Query < GraphQL::Schema::Object
      # manufacturers
      field :manufacturer, Manufacturer, null: true do
        argument :id, ID, required: true
      end

      # products
      field :product, Product, null: true do
        argument :upc, ID, required: true
      end

      # storefronts
      field :storefront, Storefront, null: true do
        argument :id, ID, required: true
      end
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
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: ComposedSchema,
      fields: FIELDS_MAP.dup,
      boundaries: BOUNDARIES_MAP,
    )

    mapping = supergraph.fields_by_type_and_location
    assert_equal FIELDS_MAP.keys.sort, mapping.keys.sort - GraphQL::Stitching::Supergraph::INTROSPECTION_TYPES
    assert_equal ["address", "id", "name"], mapping["Manufacturer"]["manufacturers"].sort
    assert_equal ["id", "products"], mapping["Manufacturer"]["products"].sort
  end

  def test_locations_by_type
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: ComposedSchema,
      fields: FIELDS_MAP.dup,
      boundaries: BOUNDARIES_MAP,
    )

    mapping = supergraph.locations_by_type
    assert_equal FIELDS_MAP.keys.sort, mapping.keys.sort - GraphQL::Stitching::Supergraph::INTROSPECTION_TYPES
    assert_equal ["manufacturers", "products"], mapping["Manufacturer"].sort
    assert_equal ["products", "storefronts"], mapping["Product"].sort
  end

  def test_possible_keys_for_type_and_location
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: ComposedSchema,
      fields: FIELDS_MAP.dup,
      boundaries: BOUNDARIES_MAP,
    )

    assert_equal ["upc"], supergraph.possible_keys_for_type_and_location("Product", "products")
    assert_equal ["upc"], supergraph.possible_keys_for_type_and_location("Product", "storefronts")
    assert_equal [], supergraph.possible_keys_for_type_and_location("Product", "manufacturers")
  end

  def test_adds_supergraph_location_for_expected_introspection_types
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: ComposedSchema,
      fields: FIELDS_MAP.dup,
      boundaries: BOUNDARIES_MAP,
    )

    ["__Schema", "__Type", "__Field"].each do |introspection_type|
      assert supergraph.locations_by_type_and_field[introspection_type], "Missing introspection type"
      assert_equal ["__super"], supergraph.locations_by_type_and_field[introspection_type].values.first
    end
  end

  def test_assign_location_resource_as_schema
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: ComposedSchema,
      fields: FIELDS_MAP.dup,
      boundaries: BOUNDARIES_MAP,
    )

    assert_equal 1, supergraph.resources.length
    subschema = Schemas::Example::Products
    supergraph.assign_location_resource("products", subschema)

    assert_equal 2, supergraph.resources.length
    assert_equal subschema, supergraph.resources["products"]
  end

  def test_assign_location_resource_as_remote_client
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: ComposedSchema,
      fields: FIELDS_MAP.dup,
      boundaries: BOUNDARIES_MAP,
    )

    client = GraphQL::Stitching::RemoteClient.new(url: "http://localhost:3000")

    assert_equal 1, supergraph.resources.length
    supergraph.assign_location_resource("products", client)

    assert_equal 2, supergraph.resources.length
    assert_equal client, supergraph.resources["products"]
  end

  def test_assign_location_resource_as_proc
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: ComposedSchema,
      fields: FIELDS_MAP.dup,
      boundaries: BOUNDARIES_MAP,
    )

    client = ->() { true }

    assert_equal 1, supergraph.resources.length
    supergraph.assign_location_resource("products", client)

    assert_equal 2, supergraph.resources.length
    assert_equal client, supergraph.resources["products"]
  end

  def test_assign_location_resource_as_block
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: ComposedSchema,
      fields: FIELDS_MAP.dup,
      boundaries: BOUNDARIES_MAP,
    )

    assert_equal 1, supergraph.resources.length
    supergraph.assign_location_resource("products") { true }

    assert_equal 2, supergraph.resources.length
    assert supergraph.resources["products"].respond_to?(:call)
  end

  def test_route_type_to_locations_connects_types_across_locations
    a = %{
      type T { upc:ID! }
      type Query { a(upc:ID!):T @stitch(key: "upc") }
    }
    b = %{
      type T { id:ID! upc:ID! }
      type Query {
        ba(upc:ID!):T @stitch(key: "upc")
        bc(id:ID!):T @stitch(key: "id")
      }
    }
    c = %{
      type T { id:ID! }
      type Query { c(id:ID!):T @stitch(key: "id") }
    }

    supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c })

    routes = supergraph.route_type_to_locations("T", "a", ["b", "c"])
    assert_equal ["b"], routes["b"].map { _1["location"] }
    assert_equal ["b", "c"], routes["c"].map { _1["location"] }

    routes = supergraph.route_type_to_locations("T", "b", ["a", "c"])
    assert_equal ["a"], routes["a"].map { _1["location"] }
    assert_equal ["c"], routes["c"].map { _1["location"] }

    routes = supergraph.route_type_to_locations("T", "c", ["a", "b"])
    assert_equal ["b", "a"], routes["a"].map { _1["location"] }
    assert_equal ["b"], routes["b"].map { _1["location"] }
  end

  def test_route_type_to_locations_favors_longer_paths_through_necessary_locations
    a = %{
      type T { id:ID! }
      type Query { a(id:ID!):T @stitch(key: "id") }
    }
    b = %{
      type T { id:ID! upc:ID! }
      type Query {
        ba(id:ID!):T @stitch(key: "id")
        bc(upc:ID!):T @stitch(key: "upc")
      }
    }
    c = %{
      type T { upc:ID! gid:ID! }
      type Query {
        cb(upc:ID!):T @stitch(key: "upc")
        cd(gid:ID!):T @stitch(key: "gid")
      }
    }
    d = %{
      type T { gid:ID! code:ID! }
      type Query {
        dc(gid:ID!):T @stitch(key: "gid")
        de(code:ID!):T @stitch(key: "code")
      }
    }
    e = %{
      type T { code:ID! id:ID! }
      type Query {
        ed(code:ID!):T @stitch(key: "code")
        ea(id:ID!):T @stitch(key: "id")
      }
    }

    supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c, "d" => d, "e" => e })

    routes = supergraph.route_type_to_locations("T", "a", ["b", "c", "d"])
    assert_equal ["b", "c", "d"], routes["d"].map { _1["location"] }
    assert routes.none? { |_key, path| path.any? { _1["location"] == "e" } }
  end

  def test_route_type_to_locations_returns_nil_for_unreachable_locations
    a = %{
      type T { upc:ID! }
      type Query { a(upc:ID!):T @stitch(key: "upc") }
    }
    b = %{
      type T { id:ID! }
      type Query { b(id:ID!):T @stitch(key: "id") }
    }
    c = %{
      type T { id:ID! }
      type Query { c(id:ID!):T @stitch(key: "id") }
    }

    supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c })

    routes = supergraph.route_type_to_locations("T", "b", ["a", "c"])
    assert_equal ["c"], routes["c"].map { _1["location"] }
    assert_nil routes["a"]
  end
end
