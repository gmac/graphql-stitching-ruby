## GraphQL Stitching for Ruby

GraphQL stitching composes a single schema from multiple underlying GraphQL resources, then smartly proxies portions of incoming requests to their respective locations in dependency order and returns the merged results. This allows an entire location graph to be queried through one combined GraphQL surface area.

![Stitched graph](./docs/images/stitching.png)

**Supports:**
- Merged object and abstract types.
- Multiple keys per merged type.
- Shared objects, fields, enums, and inputs across locations.
- Combining local and remote schemas.
- Type merging via arbitrary queries or federation `_entities` protocol.
- File uploads via [multipart form spec](https://github.com/jaydenseric/graphql-multipart-request-spec).

**NOT Supported:**
- Computed fields (ie: federation-style `@requires`).
- Subscriptions, defer/stream.

This Ruby implementation is a sibling to [GraphQL Tools](https://the-guild.dev/graphql/stitching) (JS) and [Bramble](https://movio.github.io/bramble/) (Go), and its capabilities fall somewhere in between them. GraphQL stitching is similar in concept to [Apollo Federation](https://www.apollographql.com/docs/federation/), though more generic. While Ruby is not the fastest language for a purely high-throughput API gateway, the opportunity here is for a Ruby application to stitch its local schemas together or onto remote sources without requiring an additional proxy service running in another language.

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

The quickest way to start is to use the provided [`Client`](./docs/client.md) component that wraps a stitched graph in an executable workflow with [caching hooks](./docs/client.md#cache-hooks):

```ruby
movies_schema = <<~GRAPHQL
  type Movie { id: ID! name: String! }
  type Query { movie(id: ID!): Movie }
GRAPHQL

showtimes_schema = <<~GRAPHQL
  type Showtime { id: ID! time: String! }
  type Query { showtime(id: ID!): Showtime }
GRAPHQL

client = GraphQL::Stitching::Client.new(locations: {
  movies: {
    schema: GraphQL::Schema.from_definition(movies_schema),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3000"),
  },
  showtimes: {
    schema: GraphQL::Schema.from_definition(showtimes_schema),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001"),
  },
  my_local: {
    schema: MyLocal::GraphQL::Schema,
  },
})

result = client.execute(
  query: "query FetchFromAll($movieId:ID!, $showtimeId:ID!){
    movie(id:$movieId) { name }
    showtime(id:$showtimeId): { time }
    myLocalField
  }",
  variables: { "movieId" => "1", "showtimeId" => "2" },
  operation_name: "FetchFromAll"
)
```

Schemas provided in [location settings](./docs/composer.md#performing-composition) may be class-based schemas with local resolvers (locally-executable schemas), or schemas built from SDL strings (schema definition language parsed using `GraphQL::Schema.from_definition`) and mapped to remote locations. See [composer docs](./docs/composer.md#merge-patterns) for more information on how schemas get merged.

While the `Client` constructor is an easy quick start, the library also has several discrete components that can be assembled into custom workflows:

- [Composer](./docs/composer.md) - merges and validates many schemas into one supergraph.
- [Supergraph](./docs/supergraph.md) - manages the combined schema, location routing maps, and executable resources. Can be exported, cached, and rehydrated.
- [Request](./docs/request.md) - prepares a requested GraphQL document and variables for stitching.
- [Planner](./docs/planner.md) - builds a cacheable query plan for a request document.
- [Executor](./docs/executor.md) - executes a query plan with given request variables.
- [HttpExecutable](./docs/http_executable.md) - proxies requests to remotes with multipart file upload support.

## Merged types

`Object` and `Interface` types may exist with different fields in different graph locations, and will get merged together in the combined schema.

![Merging types](./docs/images/merging.png)

To facilitate this merging of types, stitching must know how to cross-reference and fetch each variant of a type from its source location. This can be done using [arbitrary queries](#merged-types-via-arbitrary-queries) or [federation entities](#merged-types-via-federation-entities).

### Merged types via arbitrary queries

Types can merge through arbitrary queries using the `@stitch` directive:

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

catalog_schema = <<~GRAPHQL
  directive @stitch(key: String!) repeatable on FIELD_DEFINITION

  type Product {
    id: ID!
    price: Float!
  }

  type Query {
    products(ids: [ID!]!): [Product]! @stitch(key: "id")
  }
GRAPHQL

client = GraphQL::Stitching::Client.new(locations: {
  products: {
    schema: GraphQL::Schema.from_definition(products_schema),
    executable:  GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001"),
  },
  catalog: {
    schema: GraphQL::Schema.from_definition(shipping_schema),
    executable:  GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3002"),
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
* The `key: "id"` parameter indicates that an `{ id }` must be selected from prior locations so it may be submitted as an argument to this query. The query argument used to send the key is inferred when possible ([more on arguments](#multiple-query-arguments) later).

Each location that provides a unique variant of a type must provide at least one stitching query. The exception to this requirement are [foreign key types](./docs/mechanics.md##modeling-foreign-keys-for-stitching) that contain only a single key field:

```graphql
type Product {
  id: ID!
}
```

The above representation of a `Product` type provides no unique data beyond a key that is available in other locations. Thus, this representation will never require an inbound request to fetch it, and its stitching query may be omitted.

#### List queries

It's okay ([even preferable](#batching) in most circumstances) to provide a list accessor as a stitching query. The only requirement is that both the field argument and return type must be lists, and the query results are expected to be a mapped set with `null` holding the position of missing results.

```graphql
type Query {
  products(ids: [ID!]!): [Product]! @stitch(key: "id")
}

# input:  ["1", "2", "3"]
# result: [{ id: "1" }, null, { id: "3" }]
```

See [error handling](./docs/mechanics.md#stitched-errors) tips for list queries.

#### Abstract queries

It's okay for stitching queries to be implemented through abstract types. An abstract query will provide access to all of its possible types by default, each of which must implement the named key selection.

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

To customize which types a query provides (useful for unions), you may extend the `@stitch` directive with a `__typename` argument and then declare keys for a limited set of types.

```graphql
directive @stitch(key: String!, __typename: String) repeatable on FIELD_DEFINITION

type Product { upc: ID! }
type Order { id: ID! }
type Discount { code: ID! }
union Entity = Product | Order | Discount

type Query {
  entity(key: ID!): Entity @stitch(key: "upc", __typename: "Product") @stitch(key: "id", __typename: "Order")
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

The `@stitch` directive is also repeatable, allowing a single query to associate with multiple keys:

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

### Merged types via Federation entities

The [Apollo Federation specification](https://www.apollographql.com/docs/federation/subgraph-spec/) defines a standard interface for accessing merged type variants across locations. Stitching can utilize a _subset_ of this interface to facilitate basic type merging. The following spec is supported:

- `@key(fields: "id")` (repeatable) specifies a key field for an object type. The key `fields` argument may only contain one field selection.
- `_Entity` is a union type that must contain all types that implement a `@key`.
- `_Any` is a scalar that recieves raw JSON objects; each object representation contains a `__typename` and the type's key field.
- `_entities(representations: [_Any!]!): [_Entity]!` is a root query for local entity types.

The composer will automatcially detect and stitch schemas with an `_entities` query, for example:

```ruby
products_schema = <<~GRAPHQL
  directive @key(fields: String!) repeatable on OBJECT

  type Product @key(fields: "id") {
    id: ID!
    name: String!
  }

  union _Entity = Product
  scalar _Any

  type Query {
    user(id: ID!): User
    _entities(representations: [_Any!]!): [_Entity]!
  }
GRAPHQL

catalog_schema = <<~GRAPHQL
  directive @key(fields: String!) repeatable on OBJECT

  type Product @key(fields: "id") {
    id: ID!
    price: Float!
  }

  union _Entity = Product
  scalar _Any

  type Query {
    _entities(representations: [_Any!]!): [_Entity]!
  }
GRAPHQL

client = GraphQL::Stitching::Client.new(locations: {
  products: {
    schema: GraphQL::Schema.from_definition(products_schema),
    executable: ...,
  },
  catalog: {
    schema: GraphQL::Schema.from_definition(catalog_schema),
    executable: ...,
  },
})
```

It's perfectly fine to mix and match schemas that implement an `_entities` query with schemas that implement `@stitch` directives; the protocols achieve the same result. Note that stitching is much simpler than Apollo Federation by design, and that Federation's advanced routing features (such as the `@requires` and `@external` directives) will not work with stitching.

## Executables

An executable resource performs location-specific GraphQL requests. Executables may be `GraphQL::Schema` classes, or any object that responds to `.call(request, source, variables)` and returns a raw GraphQL response:

```ruby
class MyExecutable
  def call(request, source, variables)
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
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001", headers: { ... }),
  },
  third: {
    schema: ThirdSchema,
    executable: MyExecutable.new,
  },
  fourth: {
    schema: FourthSchema,
    executable: ->(req, query, vars) { ... },
  },
})
```

The `GraphQL::Stitching::HttpExecutable` class is provided as a simple executable wrapper around `Net::HTTP.post` with [file upload](./docs/http_executable.md#graphql-file-uploads) support. You should build your own executables to leverage your existing libraries and to add instrumentation. Note that you must manually assign all executables to a `Supergraph` when rehydrating it from cache ([see docs](./docs/supergraph.md)).

## Batching

The stitching executor automatically batches subgraph requests so that only one request is made per location per generation of data. This is done using batched queries that combine all data access for a given a location. For example:

```graphql
query MyOperation_2 {
  _0_result: widgets(ids:["a","b","c"]) { ... } # << 3 Widget
  _1_0_result: sprocket(id:"x") { ... } # << 1 Sprocket
  _1_1_result: sprocket(id:"y") { ... } # << 1 Sprocket
  _1_2_result: sprocket(id:"z") { ... } # << 1 Sprocket
}
```

Tips:

* List queries (like the `widgets` selection above) are more compact for accessing multiple records, and are therefore preferable as stitching accessors.
* Assure that root field resolvers across your subgraph implement batching to anticipate cases like the three `sprocket` selections above.

Otherwise, there's no developer intervention necessary (or generally possible) to improve upon data access. Note that multiple generations of data may still force the executor to return to a previous location for more data.

## Concurrency

The [Executor](./docs/executor.md) component builds atop the Ruby fiber-based implementation of `GraphQL::Dataloader`. Non-blocking concurrency requires setting a fiber scheduler via `Fiber.set_scheduler`, see [graphql-ruby docs](https://graphql-ruby.org/dataloader/nonblocking.html). You may also need to build your own remote clients using corresponding HTTP libraries.

## Additional topics

- [Modeling foreign keys for stitching](./docs/mechanics.md##modeling-foreign-keys-for-stitching)
- [Deploying a stitched schema](./docs/mechanics.md#deploying-a-stitched-schema)
- [Field selection routing](./docs/mechanics.md#field-selection-routing)
- [Root selection routing](./docs/mechanics.md#root-selection-routing)
- [Stitched errors](./docs/mechanics.md#stitched-errors)
- [Null results](./docs/mechanics.md#null-results)

## Examples

This repo includes working examples of stitched schemas running across small Rack servers. Clone the repo, `cd` into each example and try running it following its README instructions.

- [Merged types](./examples/merged_types)
- [File uploads](./examples/file_uploads)

## Tests

```shell
bundle install
bundle exec rake test [TEST=path/to/test.rb]
```
