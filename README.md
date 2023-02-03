## GraphQL Stitching for Ruby

GraphQL Stitching composes a single GraphQL schema from multiple underlying GraphQL resources, then smartly delegates portions of incoming requests to their respective service locations in dependency order and returns the merged results. This allows an entire location graph to be queried through one combined GraphQL surface area.

![Stitching Graph](./docs/images/stitching.png)

**Supports:**
- Merged object and interface types.
- Multiple keys per merged type.
- Shared objects, enums, and inputs across locations.
- Combining local and remote schemas.

**NOT Supported:**
- Computed fields (ie: federation-style `@requires`)
- Subscriptions

This Ruby implementation borrows ideas from [GraphQL Tools](https://the-guild.dev/graphql/stitching) and [Bramble](https://movio.github.io/bramble/), and its capabilities fall somewhere in between them. GraphQL stitching is similar in concept to [Apollo Federation](https://www.apollographql.com/docs/federation/), though more generic. While Ruby is not the fastest language for a high-throughput API gateway, the opportunity here is for a smaller Ruby application to stitch its local schema onto a remote schema (making itself a superset of the remote) without requiring an additional gateway service.

## Getting Started

Add to your Gemfile:

```ruby
gem "graphql-stitching"
```

Then run `bundle install`.

## Usage

The quickest way start is to use the provided `Gateway` component that assembles a stitched graph ready to execute requests:

**@todo - need to actually build this `Gateway` component...**

```ruby
movies_schema = "
  type Movie { id: ID! name: String! }
  type Query { movie(id: ID!): Movie }
"

showtimes_schema = "
  type Showtime { id: ID! time: String! }
  type Query { showtime(id: ID!): Showtime }
"

gateway = GraphQL::Stitching::Gateway.new({
  products: {
    schema: GraphQL::Schema.from_definition(products_schema),
    url: "http://localhost:3000"
  },
  showtimes: {
    schema: GraphQL::Schema.from_definition(showtimes_schema),
    url: "http://localhost:3001"
  },
  local: {
    schema: MyLocal::GraphQL::Schema
  },
})

result = gateway.execute(
  query: "query FetchFromBoth($movieId:ID!, $showtimeId:ID!){
    movie(id:$movieId) { name }
    showtime(id:$showtimeId): { time }
  }",
  variables: { "movieId" => "1", "showtimeId" => "2" },
  operation_name: "FetchFromBoth"
)
```

Schemas provided to the `Gateway` constructor may be class-based schemas with local resolvers (locally-executable schemas), or schemas built from SDL strings (schema definition language parsed using `GraphQL::Schema.from_definition`) and mapped to remote locations.

While the `Gateway` component is an easy quick start, this library has several discrete components that can be composed into tailored workflows:

- [Composer](./docs/composer.md) - merges and validates many schemas into one graph.
- [Supergraph](./docs/supergraph.md) - manages the combined schema and location routing maps. Can be exported, cached, and rehydrated.
- [Planner](./docs/planner.md) - builds a cacheable query plan for a parsed GraphQL request.
- [Executor](./docs/executor.md) - executes a query plan with given request variables.
- [Resolver](./docs/resolver.md) - shapes an execution result to match the original request.

## Merged Types (Boundaries)

`Object` and `Interface` types may exist with different fields in different graph locations, and will get merged together in the combined schema.

![Merging Types](./docs/images/merging.png)

To facilitate this merging of types, stitching needs to know how to cross-reference and fetch each version of a type from its source location. This is done using the `@boundary` directive:

```graphql
directive @boundary(key: String!) repeatable on FIELD_DEFINITION
```

The boundary directive is applied to root queries where a boundary type may be accessed in each service, and a `key` argument specifies a field needed from other services to be used as a query argument.

```ruby
products_schema = <<~GRAPHQL
  directive @boundary(key: String!) repeatable on FIELD_DEFINITION
  type Product {
    id: ID!
    name: String!
  }
  type Query {
    product(id: ID!): Product @boundary(key: "id")
  }
GRAPHQL

shipping_schema = <<~GRAPHQL
  directive @boundary(key: String!) repeatable on FIELD_DEFINITION
  type Product {
    id: ID!
    weight: Float!
  }
  type Query {
    products(ids: [ID!]!): [Product]! @boundary(key: "id")
  }
GRAPHQL

superschema = GraphQL::Stitching::Composer.new({
  "products" => GraphQL::Schema.from_definition(products_schema),
  "shipping" => GraphQL::Schema.from_definition(shipping_schema),
})

superschema.assign_location_url("products", "http://localhost:3001")
superschema.assign_location_url("shipping", "http://localhost:3002")
```

Focusing on the `@boundary` directive useage:

```graphql
type Product {
  id: ID!
  name: String!
}
type Query {
  product(id: ID!): Product @boundary(key: "id")
}
```

* The `@boundary` directive is applied to a root query where the boundary type may be accessed. The boundary type is inferred from the field return.
* The `key: "id"` parameter indicates that an `{ id }` must be selected from prior locations so it may be submitted as an argument to this query. The query argument used to send the key is inferred when possible (more on arguments later).

Each location that provides a unique version of a type must provide _exactly one_ boundary query per possible key (more on multiple keys later). The exception to this requirement are types that contain only a single key field:

```graphql
type Product {
  id: ID!
}
```

The above representation of a `Product` type provides no unique data beyond a key that is available in other locations. Thus, this representation will never require an inbound request to fetch it, and its boundary query may be omitted. This pattern of providing key-only types is very common in stitching: it allows a foreign key to be represented as an object stub that may be enriched by data collected from other locations.

#### List boundaries

It's okay (even preferable in many circumstances) to provide a list accessor as a boundary query. The only requirement is that both the field argument and return type must be lists, and the query results are expected to be a mapped set with `null` holding the position of missing results.

```graphql
type Query {
  products(ids: [ID!]!): [Product]! @boundary(key: "id")
}
```

#### Abstract boundaries

It's okay for boundary queries to be implemented through abstract types. An abstract query will provide boundaries for all of its possible types. For interfaces, the key selection should match a field within the interface, and must be implemented by all locations. For unions, all possible types must implement the key selection individually.

```graphql
interface Node {
  id: ID!
}
type Product implements Node {
  id: ID!
  name: String!
}
type Query {
  nodes(ids: [ID!]!): [Node]! @boundary(key: "id")
}
```

@todo - do we allow typed keys for abstracts...? `@boundary(key: "...on Product{ upc } ...on Post{ id }")`

#### Multiple boundary arguments

Stitching infers which argument to use for boundary queries with a single argument. For queries that accept multiple arguments, the key must provide an argument mapping specified as `"<arg>:<key>"`. Note the `"id:id"` key:

```graphql
type Query {
  product(id: ID, upc: ID): Product @boundary(key: "id:id")
}
```

#### Multiple boundary keys

A type may exist in multiple locations across the graph using different keys, for example:

```graphql
type Product { id:ID! }          # storefronts location
type Product { id:ID! upc:ID! }  # products location
type Product { upc:ID! }         # catelog location
```

In the above graph, the Storefront and Catelog locations have different keys that join through an intermediary with both. This pattern is perfectly valid and resolvable as long as the intermediary provides boundaries for each possible key:

```graphql
type Product {
  id: ID!
  upc: ID!
}
type Query {
  productById(id: ID): Product @boundary(key: "id")
  productByUpc(upc: ID): Product @boundary(key: "upc")
}
```

The boundary directive is also repeatable, allowing a single query to associate with multiple boundary keys:

```graphql
type Product {
  id: ID!
  upc: ID!
}
type Query {
  product(id: ID, upc: ID): Product @boundary(key: "id:id") @boundary(key: "upc:upc")
}
```

#### Class-based boundary schema

The `@boundary` directive can be added to class-based schemas using the following:

```ruby
class Boundary < GraphQL::Schema::Directive
  graphql_name "boundary"
  locations FIELD_DEFINITION
  repeatable true
  argument :key, String, required: true
end

class Query < GraphQL::Schema::Object
  field :product, Product, null: false do
    directive Boundary, key: "id"
    argument :id, ID, required: true
  end
end
```

## Example

This repo includes a working example of three stitched schemas running across Rack servers. Try running it:

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

The above query collects data from all three locations, two of which are remote schemas and the third a local schema. The combined graph schema is also stitched in to provide introspection capabilities.

## Tests

```shell
bundle install
bundle exec rake test [TEST=path/to/test.rb]
```
