# frozen_string_literal: true

module BasicGraph
  # type Query {
  #   product(id: ID!): Product @boundary(selection: "id")
  #   product(key: ID!): Product @boundary(selection: "key:id")
  #   node(id: ID!): Node @boundary(selection: "id ...on Product { upc }")
  # }

  LOCATIONS_MAP = {
    "manufacturers" => {
      "url" => "http://localhost:2003",
    },
    "products" => {
      "url" => "http://localhost:2002",
    },
    "storefronts" => {
      "url" => "http://localhost:2001",
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

  class Product < GraphQL::Schema::Object
    # products, storefronts
    field :upc, ID, null: false
    # products
    field :name, String, null: false
    # products
    field :price, Int, null: false
    # products
    field :manufacturer, "GraphqlStitching::Manufacturer", null: false
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

    def products
      [{ upc: 1 }, { upc: 7 }]
    end
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

  class TestSchema < GraphQL::Schema
    query Query
  end
end
