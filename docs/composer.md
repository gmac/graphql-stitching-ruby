## GraphQL::Stitching::Composer

The `Composer` receives many individual `GraphQL:Schema` instances for various graph locations and _composes_ them into a combined [`Supergraph`](./supergraph.md) that is validated for integrity. The resulting context provides a combined GraphQL schema and delegation maps used to route incoming requests:

```ruby
storefronts_sdl = <<~GRAPHQL
  type Storefront { 
    id:ID!
    name: String!
    products: [Product]
  }

  type Product { 
    id:ID!
  }

  type Query {
    storefront(id: ID!): Storefront
  }
GRAPHQL

products_sdl = <<~GRAPHQL
  directive @boundary(key: String!) repeatable on FIELD_DEFINITION

  type Product { 
    id:ID!
    name: String
    price: Int
  }

  type Query {
    product(id: ID!): Product @boundary(key: "id")
  }
GRAPHQL

supergraph = GraphQL::Stitching::Composer.new({
  "storefronts" => GraphQL::Schema.from_definition(storefronts_sdl),
  "products" => GraphQL::Schema.from_definition(products_sdl),
}).perform

combined_schema = supergraph.schema
```

The individual schemas provided to the composer are assigned a location name based on their input key. These source schemas may be built from SDL (Schema Definition Language) strings using `GraphQL::Schema.from_definition`, or may be structured Ruby classes that inherit from `GraphQL::Schema`. The source schemas are used exclusively for type reference and do NOT need any real data resolvers. Likewise, the resulting combined schema is only used for type reference and resolving introspections.

### Merge patterns

The strategy used to merge source schemas into the combined schema is based on each element type:

- `Object` and `Interface` types merge their fields together:
  - Common fields across locations must share a value type, and the weakest nullability is used.
  - Field arguments merge using the same rules as `InputObject`.
  - Objects with unique fields across locations must implement [`@boundary` accessors](../README.md#merged-types-boundaries).
  - Shared object types without `@boundary` accessors must contain identical fields.
  - Merged interfaces must remain compatible with all underlying implementations.

- `InputObject` types intersect arguments from across locations (arguments must appear in all locations):
  - Arguments must share a value type, and the strictest nullability across locations is used.
  - Composition fails if argument intersection would eliminate a non-null argument.

- `Enum` types merge their values based on how the enum is used:
  - Enums used anywhere as an argument will intersect their values (common values across all locations).
  - Enums used exclusively in read contexts will provide a union of values (all values across all locations).

- `Union` types merge all possible types from across all locations.

- `Scalar` types are added for all scalar names across all locations.

Note that the structure of a composed schema may change based on new schema additions and/or element usage (ie: changing input object arguments in one service may cause the intersection of arguments to change). Therefore, it's highly recommended that you use a [schema comparator](https://github.com/xuorig/graphql-schema_comparator) to flag regressions across composed schema versions.
