## Merged types via Apollo Federation `_entities`

The [Apollo Federation specification](https://www.apollographql.com/docs/federation/subgraph-spec/) defines a standard interface for accessing merged type variants across locations. Stitching can utilize a _subset_ of this interface to facilitate basic type merging; the full spec is NOT supported and therefore is not fully interchangable with an Apollo Gateway.

To avoid confusion, using [basic resolver queries](../README.md#merged-type-resolver-queries) is recommended unless you specifically need to interact with a service built for an Apollo ecosystem. Even then, be wary that it does not exceed the supported spec by [using features that will not work](#federation-features-that-will-most-definitly-break).

### Supported spec

The following subset of the federation spec is supported:

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

It's perfectly fine to mix and match schemas that implement an `_entities` query with schemas that implement `@stitch` directives; the protocols achieve the same result.

### Federation features that will most definitly break

- `@external` fields will confuse the stitching query planner.
- `@requires` fields will not be sent any dependencies.
- No support for Apollo composition directives.
