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
end