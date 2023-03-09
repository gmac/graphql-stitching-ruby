## GraphQL Stitching for Ruby

GraphQL stitching composes a single schema from multiple underlying GraphQL resources, then smartly delegates portions of incoming requests to their respective service locations in dependency order and returns the merged results. This allows an entire location graph to be queried through one combined GraphQL surface area.

![Stitched graph](./docs/images/stitching.png)

**Supports:**
- Merged object and interface types.
- Multiple keys per merged type.
- Shared objects, fields, enums, and inputs across locations.
- Combining local and remote schemas.

**NOT Supported:**
- Computed fields (ie: federation-style `@requires`).
- Subscriptions, defer/stream.

This Ruby implementation is a sibling to [GraphQL Tools](https://the-guild.dev/graphql/stitching) (JS) and [Bramble](https://movio.github.io/bramble/) (Go), and its capabilities fall somewhere in between them. GraphQL stitching is similar in concept to [Apollo Federation](https://www.apollographql.com/docs/federation/), though more generic. While Ruby is not the fastest language for a high-throughput API gateway, the opportunity here is for a Ruby application to stitch its local schema onto a remote schema (making itself a superset of the remote) without requiring an additional gateway service.

## Getting started

Add to your Gemfile:

```ruby
gem "graphql-stitching"
```

Run `bundle install`, then require unless running an autoloading framework (Rails, etc):

```ruby
require "graphql/stitching"
```

## Usage

The quickest way to start is to use the provided [`Gateway`](./docs/gateway.md) component that wraps a stitched graph in an executable workflow with [caching hooks](./docs/gateway.md#cache-hooks):

```ruby
movies_schema = <<~GRAPHQL
  type Movie { id: ID! name: String! }
  type Query { movie(id: ID!): Movie }
GRAPHQL

showtimes_schema = <<~GRAPHQL
  type Showtime { id: ID! time: String! }
  type Query { showtime(id: ID!): Showtime }
GRAPHQL

gateway = GraphQL::Stitching::Gateway.new(locations: {
  movies: {
    schema: GraphQL::Schema.from_definition(movies_schema),
    executable: GraphQL::Stitching::RemoteClient.new(url: "http://localhost:3000"),
  },
  showtimes: {
    schema: GraphQL::Schema.from_definition(showtimes_schema),
    executable: GraphQL::Stitching::RemoteClient.new(url: "http://localhost:3001"),
  },
  my_local: {
    schema: MyLocal::GraphQL::Schema,
  },
})

result = gateway.execute(
  query: "query FetchFromAll($movieId:ID!, $showtimeId:ID!){
    movie(id:$movieId) { name }
    showtime(id:$showtimeId): { time }
    myLocalField
  }",
  variables: { "movieId" => "1", "showtimeId" => "2" },
  operation_name: "FetchFromAll"
)
```

Schemas provided to the `Gateway` constructor may be class-based schemas with local resolvers (locally-executable schemas), or schemas built from SDL strings (schema definition language parsed using `GraphQL::Schema.from_definition`) and mapped to remote locations. See [composer docs](./docs/composer.md#merge-patterns) for more information on how schemas get merged.

While the [`Gateway`](./docs/gateway.md) constructor is an easy quick start, the library also has several discrete components that can be assembled into custom workflows:

- [Composer](./docs/composer.md) - merges and validates many schemas into one supergraph.
- [Supergraph](./docs/supergraph.md) - manages the combined schema, location routing maps, and executable resources. Can be exported, cached, and rehydrated.
- [Request](./docs/request.md) - prepares a requested GraphQL document and variables for stitching.
- [Planner](./docs/planner.md) - builds a cacheable query plan for a request document.
- [Executor](./docs/executor.md) - executes a query plan with given request variables.

## Merged types

`Object` and `Interface` types may exist with different fields in different graph locations, and will get merged together in the combined schema.

![Merging types](./docs/images/merging.png)

To facilitate this merging of types, stitching must know how to cross-reference and fetch each variant of a type from its source location. This is done using the `@stitch` directive:

```graphql
directive @stitch(key: String!) repeatable on FIELD_DEFINITION
```

This directive (or [static configuration](#sdl-based-schemas)) is applied to root queries where a merged type may be accessed in each location, and a `key` argument specifies a field needed from other locations to be used as a query argument.

```ruby
products_schema = <<~GRAPHQL
  directive @stitch(key: String!) repeatable on FIELD_DEFINITION

  type Product {
    id: ID!
    name: String!
  }

  type Query {
    product(id: ID!): Product @stitch(key: "id")
  }
GRAPHQL

shipping_schema = <<~GRAPHQL
  directive @stitch(key: String!) repeatable on FIELD_DEFINITION

  type Product {
    id: ID!
    weight: Float!
  }

  type Query {
    products(ids: [ID!]!): [Product]! @stitch(key: "id")
  }
GRAPHQL

supergraph = GraphQL::Stitching::Composer.new.perform({
  products: {
    schema: GraphQL::Schema.from_definition(products_schema),
    executable:  GraphQL::Stitching::RemoteClient.new(url: "http://localhost:3001"),
  },
  shipping: {
    schema: GraphQL::Schema.from_definition(shipping_schema),
    executable:  GraphQL::Stitching::RemoteClient.new(url: "http://localhost:3002"),
  },
})
```

Focusing on the `@stitch` directive usage:

```graphql
type Product {
  id: ID!
  name: String!
}
type Query {
  product(id: ID!): Product @stitch(key: "id")
}
```

* The `@stitch` directive is applied to a root query where the merged type may be accessed. The merged type identity is inferred from the field return.
* The `key: "id"` parameter indicates that an `{ id }` must be selected from prior locations so it may be submitted as an argument to this query. The query argument used to send the key is inferred when possible (more on arguments later).

Each location that provides a unique variant of a type must provide _exactly one_ stitching query per possible key (more on multiple keys later). The exception to this requirement are types that contain only a single key field:

```graphql
type Product {
  id: ID!
}
```

The above representation of a `Product` type provides no unique data beyond a key that is available in other locations. Thus, this representation will never require an inbound request to fetch it, and its stitching query may be omitted. This pattern of providing key-only types is very common in stitching: it allows a foreign key to be represented as an object stub that may be enriched by data collected from other locations.

#### List queries

It's okay ([even preferable](https://www.youtube.com/watch?v=VmK0KBHTcWs) in many circumstances) to provide a list accessor as a stitching query. The only requirement is that both the field argument and return type must be lists, and the query results are expected to be a mapped set with `null` holding the position of missing results.

```graphql
type Query {
  products(ids: [ID!]!): [Product]! @stitch(key: "id")
}
```

#### Abstract queries

It's okay for stitching queries to be implemented through abstract types. An abstract query will provide access to all of its possible types. For interfaces, the key selection should match a field within the interface. For unions, all possible types must implement the key selection individually.

```graphql
interface Node {
  id: ID!
}
type Product implements Node {
  id: ID!
  name: String!
}
type Query {
  nodes(ids: [ID!]!): [Node]! @stitch(key: "id")
}
```

#### Multiple query arguments

Stitching infers which argument to use for queries with a single argument. For queries that accept multiple arguments, the key must provide an argument mapping specified as `"<arg>:<key>"`. Note the `"id:id"` key:

```graphql
type Query {
  product(id: ID, upc: ID): Product @stitch(key: "id:id")
}
```

#### Multiple type keys

A type may exist in multiple locations across the graph using different keys, for example:

```graphql
type Product { id:ID! }          # storefronts location
type Product { id:ID! upc:ID! }  # products location
type Product { upc:ID! }         # catelog location
```

In the above graph, the `storefronts` and `catelog` locations have different keys that join through an intermediary. This pattern is perfectly valid and resolvable as long as the intermediary provides stitching queries for each possible key:

```graphql
type Product {
  id: ID!
  upc: ID!
}
type Query {
  productById(id: ID!): Product @stitch(key: "id")
  productByUpc(upc: ID!): Product @stitch(key: "upc")
}
```

The `@stitch` directive is also repeatable (_requires graphql-ruby >= v2.0.15_), allowing a single query to associate with multiple keys:

```graphql
type Product {
  id: ID!
  upc: ID!
}
type Query {
  product(id: ID, upc: ID): Product @stitch(key: "id:id") @stitch(key: "upc:upc")
}
```

#### Class-based schemas

The `@stitch` directive can be added to class-based schemas with a directive class:

```ruby
class StitchField < GraphQL::Schema::Directive
  graphql_name "stitch"
  locations FIELD_DEFINITION
  repeatable true
  argument :key, String, required: true
end

class Query < GraphQL::Schema::Object
  field :product, Product, null: false do
    directive StitchField, key: "id"
    argument :id, ID, required: true
  end
end
```

The `@stitch` directive can be exported from a class-based schema to an SDL string by calling `schema.to_definition`.

#### SDL-based schemas

A clean SDL string may also have stitching directives applied via static configuration by passing a `stitch` array in [location settings](./docs/composer.md#performing-composition):

```ruby
sdl_string = <<~GRAPHQL
  type Product {
    id: ID!
    upc: ID!
  }
  type Query {
    productById(id: ID!): Product
    productByUpc(upc: ID!): Product
  }
GRAPHQL

supergraph = GraphQL::Stitching::Composer.new.perform({
  products:  {
    schema: GraphQL::Schema.from_definition(sdl_string),
    executable: ->() { ... },
    stitch: [
      { field_name: "productById", key: "id" },
      { field_name: "productByUpc", key: "upc" },
    ]
  },
  # ...
})
```

#### Custom directive names

The library is configured to use a `@stitch` directive by default. You may customize this by setting a new name during initialization:

```ruby
GraphQL::Stitching.stitch_directive = "merge"
```

## Executables

An executable resource performs location-specific GraphQL requests. Executables may be `GraphQL::Schema` classes, or any object that responds to `.call(location, source, variables, context)` and returns a raw GraphQL response:

```ruby
class MyExecutable
  def call(location, source, variables, context)
    # process a GraphQL request...
    return {
      "data" => { ... },
      "errors" => [ ... ],
    }
  end
end
```

A [Supergraph](./docs/supergraph.md) is composed with executable resources provided for each location. Any location that omits the `executable` option will use the provided `schema` as its default executable:

```ruby
supergraph = GraphQL::Stitching::Composer.new.perform({
  first: {
    schema: FirstSchema,
    # executable:^^^^^^ delegates to FirstSchema,
  },
  second: {
    schema: SecondSchema,
    executable: GraphQL::Stitching::RemoteClient.new(url: "http://localhost:3001", headers: { ... }),
  },
  third: {
    schema: ThirdSchema,
    executable: MyExecutable.new,
  },
  fourth: {
    schema: FourthSchema,
    executable: ->(loc, query, vars, ctx) { ... },
  },
})
```

The `GraphQL::Stitching::RemoteClient` class is provided as a simple executable wrapper around `Net::HTTP.post`. You should build your own executables to leverage your existing libraries and to add instrumentation. Note that you must manually assign all executables to a `Supergraph` when rehydrating it from cache ([see docs](./docs/supergraph.md)).

## Concurrency

The [Executor](./docs/executor.md) component builds atop the Ruby fiber-based implementation of `GraphQL::Dataloader`. Non-blocking concurrency requires setting a fiber scheduler via `Fiber.set_scheduler`, see [graphql-ruby docs](https://graphql-ruby.org/dataloader/nonblocking.html). You may also need to build your own remote clients using corresponding HTTP libraries.

## Example

This repo includes a working example of several stitched schemas running across small Rack servers. Try running it:

```shell
bundle install
foreman start
```

Then visit the gateway service at `http://localhost:3000` and try this query:

```graphql
query {
  storefront(id: "1") {
    id
    products {
      upc
      name
      price
      manufacturer {
        name
        address
        products { upc name }
      }
    }
  }
}
```

The above query collects data from all locations, two of which are remote schemas and the third a local schema. The combined graph schema is also stitched in to provide introspection capabilities.

## Tests

```shell
bundle install
bundle exec rake test [TEST=path/to/test.rb]
```
