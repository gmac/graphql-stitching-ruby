## Ruby GraphQL Stitching

GraphQL Stitching is the process of composing a single GraphQL schema from multiple underlying GraphQL resources, then smartly delegating portions of incoming requests to their respective service locations, and returning the merged results. This allows an entire service graph to be queried through one combined surface area.

This Ruby implementation borrows ideas from [GraphQL Tools stitching](https://the-guild.dev/graphql/stitching) and [Bramble](https://movio.github.io/bramble/), and splits the difference between them with its capabilities. GraphQL stitching as a whole is similar in concept to [Apollo Federation](https://www.apollographql.com/docs/federation/), but is much more generic.

**Supports:**
- Merged types via scalar key exchanges.
- Multiple merge keys allowed per type.
- Merged interfaces across locations.
- Enums and inputs may be shared across locations.

**NOT Supported:**
- Computed fields (ie: federation-style `@requires`)
- Subscriptions

## Getting Started

```ruby
gem "graphql-stitching"
```

```shell
bundle install
```

## Merged Boundary Types

GraphQL `Object` and `Interface` types may exist with different fields in different graph locations, and get merged together into one type in the gateway. These merged types are called "boundary types", for example:

```ruby
products_schema = "
  type Product {
    id: ID!
    name: String!
  }
  type Query {
    product(id: ID!): Product @boundary(key: "id")
  }
"

shipping_schema = "
  type Product {
    id: ID!
    weight: Float!
  }
  type Query {
    product(id: ID!): Product @boundary(key: "id")
  }
"

superschema = GraphQL::Stitching::Composer.new({
  "products" => GraphQL::Schema.from_definition(products_schema),
  "shipping" => GraphQL::Schema.from_definition(shipping_schema),
})

superschema.assign_location_url("products", "http://localhost:3001")
superschema.assign_location_url("shipping", "http://localhost:3002")
```

In the composed superschema, the `Product` type will have the fields of both locations:

```graphql
type Product {
  id: ID!
  name: String!
  weight: Float!
}
```

However, in order to resolve this type the stitched superschema must be able to access each version of the type from its respective location with a joining key to cross-reference the records by. Declaring `@boundary` queries tells the stitched superschema how to access this type in each location:

```graphql
type Product {
  id: ID!
  name: String!
}
type Query {
  product(id: ID!): Product @boundary(key: "id")
}
```

The `@boundary` directive is applied to a root query where this type can be accessed. Its `key: "id"` argument specifies that an `id` field must be selected from other services so it may be provided to this query as an argument.

### Argument aliases

When the boundary query only accepts a single argument, stitching can infer which argument to use. For boundary queries that accept multiple arguments, a selection alias must be provided to map the remote selection to its intended argument:

```graphql
type Product {
  id: ID!
  upc: ID!
  name: String!
}
type Query {
  product(id: ID, upc: ID): Product @boundary(key: "id:id")
}
```

### Multiple keys

A type may exist in multiple locations across the graph using different keys, for example:

```graphql
type Product { id:ID! }          # storefronts location
type Product { id:ID! upc:ID! }  # products location
type Product { upc:ID! }         # catelog location
```

In the above, the Storefront and Catelog locations have different keys and are joined by an intermediary that has both. This pattern is perfectly valid and resolvable.

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

```graphql
type Product {
  id: ID!
  upc: ID!
}
type Query {
  product(id: ID, upc: ID): Product @boundary(key: "id:id") @boundary(key: "upc:upc")
}
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

The above query collects data from all three services, plus introspects the combined schema. Two schemas are accessed remotely via HTTP, while the third is a local schema embedded within the gateway server itself.

## Tests

```shell
bundle install
bundle exec rake test [TEST=path/to/test.rb]
```
