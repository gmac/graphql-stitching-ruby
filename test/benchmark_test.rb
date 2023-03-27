require 'test_helper'
require 'benchmark'
require 'benchmark/memory'

storefronts_sdl = %|
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

products_sdl = %|
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

manufacturers_sdl = %|
  type Manufacturer {
    id: ID!
    name: String!
    address: String!
  }
  type Query {
    manufacturer(id: ID!): Manufacturer @stitch(key: \"id\")
  }
|

supergraph1 = compose_definitions({
  "storefronts" => storefronts_sdl,
  "products" => products_sdl,
  "manufacturers" => manufacturers_sdl,
})

supergraph2 = compose_definitions({
  "storefronts" => storefronts_sdl,
  "products" => products_sdl,
  "manufacturers" => manufacturers_sdl,
})
supergraph2.memoization = false

request = GraphQL::Stitching::Request.new(%|
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
|)


CYCLES = 50_000

Benchmark.bmbm do |x|
  x.report("with") do
    CYCLES.times do
      GraphQL::Stitching::Planner.new(
        supergraph: supergraph1,
        request: request,
      ).perform
    end
  end

  x.report("without") do
    CYCLES.times do
      GraphQL::Stitching::Planner.new(
        supergraph: supergraph2,
        request: request,
      ).perform
    end
  end

  #x.compare!
end

Benchmark.memory do |x|
  x.report("with") do
    CYCLES.times do
      GraphQL::Stitching::Planner.new(
        supergraph: supergraph1,
        request: request,
      ).perform
    end
  end

  x.report("without") do
    CYCLES.times do
      GraphQL::Stitching::Planner.new(
        supergraph: supergraph2,
        request: request,
      ).perform
    end
  end

  x.compare!
end