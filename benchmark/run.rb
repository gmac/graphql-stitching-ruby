# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "bundler/setup"
require "graphql/stitching"

STITCH_DEFINITION = "directive @stitch(key: String!, arguments: String, typeName: String) repeatable on FIELD_DEFINITION\n"

def compose_definitions(locations)
  locations = locations.each_with_object({}) do |(location, schema_config), memo|
    schema_config = STITCH_DEFINITION + schema_config if schema_config.include?("@stitch")
    memo[location.to_s] = { schema: GraphQL::Schema.from_definition(schema_config) }
  end

  GraphQL::Stitching::Composer.new.perform(locations)
end

class PlannerBenchmark
  Case = Struct.new(:name, :supergraph, :document, :variables, keyword_init: true)

  MINIMUM_SECONDS = Float(ENV.fetch("BENCHMARK_SECONDS", 2.0))
  WARMUP_ITERATIONS = Integer(ENV.fetch("BENCHMARK_WARMUP", 200))

  def initialize(cases)
    @cases = cases
  end

  def run
    width = @cases.map { |c| c.name.length }.max

    puts "GraphQL::Stitching::Planner"
    puts "ruby #{RUBY_VERSION}p#{RUBY_PATCHLEVEL} (#{RUBY_PLATFORM})"
    puts "graphql #{GraphQL::VERSION}"
    puts "minimum #{MINIMUM_SECONDS}s per case"
    puts

    @cases.each do |bench_case|
      WARMUP_ITERATIONS.times { plan(bench_case) }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      iterations = 0
      elapsed = 0.0

      loop do
        plan(bench_case)
        iterations += 1
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        break if elapsed >= MINIMUM_SECONDS
      end

      ips = iterations / elapsed
      microseconds = 1_000_000.0 / ips
      puts "%-#{width}s %10.1f i/s %10.2f us/i" % [bench_case.name, ips, microseconds]
    end
  end

  private

  def plan(bench_case)
    GraphQL::Stitching::Request.new(
      bench_case.supergraph,
      bench_case.document,
      variables: bench_case.variables,
    ).plan
  end
end

root_supergraph = compose_definitions({
  "widgets" => %|
    input MakeWidgetInput { name: String child: MakeWidgetInput }
    type Widget { id: ID! name(lang: String): String size: Int color: String }
    type Query { widget(id: ID!): Widget widgets(ids: [ID!]): [Widget!]! }
    type Mutation { makeWidget(input: MakeWidgetInput!): Widget }
  |,
  "sprockets" => %|
    input MakeSprocketInput { name: String child: MakeSprocketInput }
    type Sprocket { id: ID! name(lang: String): String size: Int color: String }
    type Query { sprocket(id: ID!): Sprocket sprockets(ids: [ID!]): [Sprocket!]! }
    type Mutation { makeSprocket(input: MakeSprocketInput!): Sprocket }
  |,
})

delegation_supergraph = compose_definitions({
  "alpha" => %|
    type Widget { id: ID! a: String! b: String! }
    type Query { alpha(id: ID!): Widget @stitch(key: "id") }
  |,
  "bravo" => %|
    type Widget { id: ID! a: String! b: String! }
    type Query { bravo(id: ID!): Widget @stitch(key: "id") }
  |,
  "charlie" => %|
    type Widget { id: ID! c: String! d: String! }
    type Query { charlie(id: ID!): Widget @stitch(key: "id") }
  |,
  "delta" => %|
    type Widget { id: ID! d: String! e: String! }
    type Query { delta(id: ID!): Widget @stitch(key: "id") }
  |,
  "echo" => %|
    type Widget { id: ID! d: String! e: String! f: String! }
    type Query { echo(id: ID!): Widget @stitch(key: "id") }
  |,
  "foxtrot" => %|
    type Widget { id: ID! d: String! f: String! }
    type Query { foxtrot(id: ID!): Widget @stitch(key: "id") }
  |,
})

resolver_supergraph = compose_definitions({
  "storefronts" => %|
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
  |,
  "products" => %|
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
  |,
  "manufacturers" => %|
    type Manufacturer {
      id: ID!
      name: String!
      address: String!
    }
    type Query {
      manufacturer(id: ID!): Manufacturer @stitch(key: "id")
    }
  |,
})

abstract_supergraph = compose_definitions({
  "a" => %|
    interface Buyable {
      id: ID!
      name: String!
      price: Float!
    }
    type Product implements Buyable {
      id: ID!
      name: String!
      price: Float!
    }
    type Query {
      products(ids: [ID!]!): [Product]! @stitch(key: "id")
    }
  |,
  "b" => %|
    interface Buyable { id: ID! }
    type Product implements Buyable { id: ID! }
    type Bundle implements Buyable {
      id: ID!
      name: String!
      price: Float!
      products: [Product]!
    }
    type Query {
      buyable(id: ID!): Buyable @stitch(key: "id")
    }
  |,
})

cases = [
  PlannerBenchmark::Case.new(
    name: "root groups",
    supergraph: root_supergraph,
    document: %|
      query($wid: ID!, $sid: ID!, $ids: [ID!], $lang: String) {
        a: widget(id: $wid) { id name(lang: $lang) size color }
        b: sprocket(id: $sid) { id name(lang: $lang) size color }
        c: widgets(ids: $ids) { id name size color }
        d: sprockets(ids: $ids) { id name size color }
      }
    |,
    variables: { "wid" => "1", "sid" => "2", "ids" => ["1", "2"], "lang" => "en" },
  ),
  PlannerBenchmark::Case.new(
    name: "variables",
    supergraph: root_supergraph,
    document: %|
      mutation($wname1: String!, $wname2: String!, $sname1: String!, $sname2: String!, $lang: String) {
        makeWidget(input: { name: $wname1, child: { name: $wname2 } }) { id name(lang: $lang) }
        makeSprocket(input: { name: $sname1, child: { name: $sname2 } }) { id name(lang: $lang) }
      }
    |,
    variables: {
      "wname1" => "a",
      "wname2" => "b",
      "sname1" => "c",
      "sname2" => "d",
      "lang" => "en",
    },
  ),
  PlannerBenchmark::Case.new(
    name: "delegation",
    supergraph: delegation_supergraph,
    document: %|query { alpha(id: "1") { a b c d e f } }|,
  ),
  PlannerBenchmark::Case.new(
    name: "nested resolvers",
    supergraph: resolver_supergraph,
    document: %|
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
    |,
  ),
  PlannerBenchmark::Case.new(
    name: "fragments",
    supergraph: resolver_supergraph,
    document: %|
      query {
        storefront(id: "1") {
          products {
            ...ProductAttrs
            manufacturer {
              ...ManufacturerAttrs
            }
          }
        }
      }
      fragment ProductAttrs on Product { name price }
      fragment ManufacturerAttrs on Manufacturer {
        name
        address
        products { ...ProductAttrs }
      }
    |,
  ),
  PlannerBenchmark::Case.new(
    name: "abstracts",
    supergraph: abstract_supergraph,
    document: %|
      query {
        buyable(id: "1") {
          ... {
            ...BuyableAttrs
          }
        }
      }
      fragment BuyableAttrs on Buyable { id name price }
    |,
  ),
]

PlannerBenchmark.new(cases).run
