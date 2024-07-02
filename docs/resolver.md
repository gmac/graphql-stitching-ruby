## GraphQL::Stitching::Resolver

A `Resolver` contains all information about a root query used by stitching to fetch location-specific variants of a merged type. Specifically, resolvers manage parsed keys and argument structures.

### Arguments

Resolvers configure arguments through a template string of [GraphQL argument literal syntax](https://spec.graphql.org/October2021/#sec-Language.Arguments). This allows sending multiple arguments that intermix stitching keys with complex object shapes and other static values.

#### Key insertions

Key values fetched from previous locations may be inserted into arguments. Key insertions are prefixed by `$` and specify a dot-notation path to any selections made by the resolver `key`, or `__typename`.

```graphql
type Query {
  entity(id: ID!, type: String!): [Entity]!
    @stitch(key: "owner { id }", arguments: "id: $.owner.id, type: $.__typename")
}
```

Key insertions are _not_ quoted to differentiate them from other literal values.

#### Lists

List arguments may specify input just like non-list arguments, and [GraphQL list input coercion](https://spec.graphql.org/October2021/#sec-List.Input-Coercion) will assume the shape represents a list item:

```graphql
type Query {
  product(ids: [ID!]!, source: DataSource!): [Product]!
    @stitch(key: "id", arguments: "ids: $.id, source: CACHE")
}
```

List resolvers (that return list types) may _only_ insert keys into repeatable list arguments, while non-list arguments may only contain static values. Nested list inputs are neither common nor practical, so are not supported.

#### Built-in scalars

Built-in scalars are written as normal literal values. For convenience, string literals may be enclosed in single quotes rather than escaped double-quotes:

```graphql
type Query {
  product(id: ID!, source: String!): Product
    @stitch(key: "id", arguments: "id: $.id, source: 'cache'")

  variant(id: ID!, limit: Int!): Variant
    @stitch(key: "id", arguments: "id: $.id, limit: 100")
}
```

All scalar usage must be legal to the resolver field's arguments schema.

#### Enums

Enum literals may be provided anywhere in the input structure. They are _not_ quoted:

```graphql
enum DataSource {
  CACHE
}
type Query {
  product(id: ID!, source: DataSource!): [Product]!
    @stitch(key: "id", arguments: "id: $.id, source: CACHE")
}
```

All enum usage must be legal to the resolver field's arguments schema.

#### Input Objects

Input objects may be provided anywhere in the input, even as nested structures. The stitching resolver will build the specified object shape:

```graphql
input ComplexKey {
  id: ID
  nested: ComplexKey
}
type Query {
  product(key: ComplexKey!): [Product]!
    @stitch(key: "id", arguments: "key: { nested: { id: $.id } }")
}
```

Input object shapes must conform to their respective schema definitions based on their placement within resolver arguments.

#### Custom scalars

Custom scalar keys allow any input shape to be submitted, from primitive scalars to complex object structures. These values will be sent and recieved as untyped JSON input:

```graphql
type Product {
  id: ID!
}
union Entity = Product
scalar Key

type Query {
  entities(representations: [Key!]!): [Entity]!
    @stitch(key: "id", arguments: "representations: { id: $.id, __typename: $.__typename }")
}
```

Custom scalar arguments have no structured schema definition to validate against. This makes them flexible but quite lax, for better or worse.
