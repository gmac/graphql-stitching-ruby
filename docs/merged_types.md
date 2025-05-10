## Merged Types

`Object` and `Interface` types may exist with different fields in different graph locations, and will get merged together in the combined supergraph schema.

![Merging types](./images/merging.png)

To facilitate this, schemas should be designed around **merged type keys** that stitching can cross-reference and fetch across locations using **type resolver queries** (discussed below). For those in an Apollo ecosystem, there's also _limited_ support for merging types though [federation `_entities`](./merged_types_apollo.md).

### Merged type keys

Foreign keys in a GraphQL schema frequently look like the `Product.imageId` field here:

```graphql
# -- Products schema:

type Product {
  id: ID!
  imageId: ID!
}

# -- Images schema:

type Image {
  id: ID!
  url: String!
}
```

However, this design does not lend itself to merging types across locations. A simple schema refactor makes this foreign key more expressive as an entity type, and turns the key into an _object_ that will merge with analogous objects in other locations:

```graphql
# -- Products schema:

type Product {
  id: ID!
  image: Image!
}

type Image {
  id: ID!
}

# -- Images schema:

type Image {
  id: ID!
  url: String!
}
```

### Merged type resolver queries

Each location that provides a unique variant of a type must provide at least one _resolver query_ for accessing it. Type resolvers are root queries identified by a `@stitch` directive:

```graphql
directive @stitch(key: String!, arguments: String, typeName: String) repeatable on FIELD_DEFINITION
```

This directive tells stitching how to cross-reference and fetch types from across locations, for example:

```ruby
products_schema = <<~GRAPHQL
  directive @stitch(key: String!, arguments: String) repeatable on FIELD_DEFINITION

  type Product {
    id: ID!
    name: String!
  }

  type Query {
    product(id: ID!): Product @stitch(key: "id")
  }
GRAPHQL

catalog_schema = <<~GRAPHQL
  directive @stitch(key: String!, arguments: String) repeatable on FIELD_DEFINITION

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
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001"),
  },
  catalog: {
    schema: GraphQL::Schema.from_definition(catalog_schema),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3002"),
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

* The `@stitch` directive marks a root query where the merged type may be accessed. The merged type identity is inferred from the field return.
* The `key: "id"` parameter indicates that an `{ id }` must be selected from prior locations so it can be submitted as an argument to this query. The query argument used to send the key is inferred when possible ([more on arguments](#argument-shapes) later).

Merged types must have a resolver query in each of their possible locations. The one exception to this requirement are [outbound-only types](#outbound-only-merged-types) that contain no exclusive data; these may omit their resolver because they never require an inbound request to fetch them.

#### List queries

It's generally preferable to provide a list accessor as a resolver query for optimal batching. The only requirement is that both the field argument and the return type must be lists, and the query results are expected to be a mapped set with `null` holding the position of missing results.

```graphql
type Query {
  products(ids: [ID!]!): [Product]! @stitch(key: "id")
}

# input:  ["1", "2", "3"]
# result: [{ id: "1" }, null, { id: "3" }]
```

See [error handling](./error_handling.md#list-queries) tips for list queries.

#### Abstract queries

It's okay for resolver queries to be implemented through abstract types. An abstract query will provide access to all of its possible types by default, each of which must implement the key.

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

To customize which types an abstract query provides and their respective keys, add a `typeName` constraint. This can be repeated to select multiple types from an abstract.

```graphql
type Product { sku: ID! }
type Order { id: ID! }
type Customer { id: ID! } # << not stitched
union Entity = Product | Order | Customer

type Query {
  entity(key: ID!): Entity
    @stitch(key: "sku", typeName: "Product")
    @stitch(key: "id", typeName: "Order")
}
```

#### Argument shapes

Stitching infers which argument to use for queries with a single argument, or when the key name matches its intended argument. For custom mappings, use the `arguments` option:

```graphql
type Product {
  id: ID!
}
union Entity = Product

type Query {
  entity(key: ID!, type: String!): Entity @stitch(
    key: "id", 
    arguments: "key: $.id, type: $.__typename",
    typeName: "Product",
  )
}
```

The `arguments` option specifies a template of [GraphQL arguments](https://spec.graphql.org/October2021/#sec-Language.Arguments) (or, GraphQL syntax that would normally be written into an arguments closure). This template may include key insertions prefixed by `$` with dot-notation paths to any selections made by the resolver `key`. A `__typename` key selection is also always available. This arguments syntax allows sending multiple arguments that intermix stitching keys with complex input shapes and/or static values.

<details>
  <summary>All argument patterns</summary>

  ---

  **List arguments**

  List arguments may specify input just like non-list arguments, and [GraphQL list input coercion](https://spec.graphql.org/October2021/#sec-List.Input-Coercion) will assume the shape represents a list item:

  ```graphql
  type Query {
    product(ids: [ID!]!, organization: ID!): [Product]!
      @stitch(key: "id", arguments: "ids: $.id, organization: '1'")
  }
  ```

  List resolvers (that return list types) may _only_ insert keys into repeatable list arguments, while non-list arguments may only contain static values. Nested list inputs are neither common nor practical, so are not supported.

  **Scalar & Enum arguments**

  Built-in scalars are written as normal literal values. For convenience, string literals may be enclosed in single quotes rather than escaped double-quotes:

  ```graphql
  enum DataSource { CACHE }
  type Query {
    product(id: ID!, source: String!): Product
      @stitch(key: "id", arguments: "id: $.id, source: 'cache'")

    variant(id: ID!, source: DataSource!): Variant
      @stitch(key: "id", arguments: "id: $.id, source: CACHE")
  }
  ```

  **InputObject arguments**

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

  **Custom scalar arguments**

  Custom scalar keys allow any input shape to be submitted, from primitive scalars to complex object structures. These values will be sent and recieved as untyped JSON input, which makes them flexible but quite lax with validation:

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

  ---
</details>

#### Composite type keys

Resolver keys may make composite selections for multiple key fields and/or nested scopes, for example:

```graphql
interface FieldOwner {
  id: ID!
}
type CustomField {
  owner: FieldOwner!
  key: String!
  value: String
}
input CustomFieldLookup {
  ownerId: ID!
  ownerType: String!
  key: String!
}

type Query {
  customFields(lookups: [CustomFieldLookup!]!): [CustomField]! @stitch(
    key: "owner { id __typename } key",
    arguments: "lookups: { ownerId: $.owner.id, ownerType: $.owner.__typename, key: $.key }"
  )
}
```

Note that composite key selections may _not_ be distributed across locations. The complete selection criteria must be available in each location that provides the key.

#### Multiple type keys

A type may exist in multiple locations across the graph using different keys, for example:

```graphql
type Product { id:ID! }          # storefronts location
type Product { id:ID! sku:ID! }  # products location
type Product { sku:ID! }         # catelog location
```

In the above graph, the `storefronts` and `catelog` locations have different keys that join through an intermediary. This pattern is perfectly valid and resolvable as long as the intermediary provides resolver queries for each possible key:

```graphql
type Product {
  id: ID!
  sku: ID!
}
type Query {
  productById(id: ID!): Product @stitch(key: "id")
  productBySku(sku: ID!): Product @stitch(key: "sku")
}
```

The `@stitch` directive is also repeatable, allowing a single query to associate with multiple keys:

```graphql
type Product {
  id: ID!
  sku: ID!
}
type Query {
  product(id: ID, sku: ID): Product @stitch(key: "id") @stitch(key: "sku")
}
```

#### Null merges

It's okay for a merged type resolver to return `null` for an object as long as all unique fields of the type allow null. For example, the following merge works:

```graphql
# -- Request

query {
  movieA(id: "23") {
    id
    title
    rating
  }
}

# -- Location A

type Movie {
  id: String!
  title: String!
}

type Query {
  movieA(id: ID!): Movie @stitch(key: "id")
      # (id: "23") -> { id: "23", title: "Jurassic Park" }
}

# -- Location B

type Movie {
  id: String!
  rating: Int
}

type Query {
  movieB(id: ID!): Movie @stitch(key: "id")
      # (id: "23") -> null
}
```

And produces this result:

```json
{
  "data": {
    "id": "23",
    "title": "Jurassic Park",
    "rating": null
  }
}
```

Location B is allowed to return `null` here because its one unique field (`rating`) is nullable. If `rating` were non-null, then null bubbling would invalidate the response object.

### Adding @stitch directives

The `@stitch` directive can be added to class-based schemas using the provided definition:

```ruby
class Query < GraphQL::Schema::Object
  field :product, Product, null: false do
    directive(GraphQL::Stitching::Directives::Stitch, key: "id")
    argument(:id, ID, required: true)
  end
end

class Schema < GraphQL::Schema
  directive(GraphQL::Stitching::Directives::Stitch)
  query(Query)
end
```

Alternatively, a clean schema can have stitching directives applied from static configuration passed as a location's `stitch` option:

```ruby
sdl_string = <<~GRAPHQL
  type Product {
    id: ID!
    sku: ID!
  }
  type Query {
    productById(id: ID!): Product
    productBySku(sku: ID!): Product
  }
GRAPHQL

client = GraphQL::Stitching::Client.new(locations: {
  products:  {
    schema: GraphQL::Schema.from_definition(sdl_string),
    executable: ->() { ... },
    stitch: [
      { field_name: "productById", key: "id" },
      { field_name: "productBySku", key: "sku", arguments: "mySku: $.sku" },
    ]
  },
  # ...
})
```

### Outbound-only merged types

Merged types do not always require a resolver query. For example:

```graphql
# -- Location A

type Widget {
  id: ID!
  name: String
  price: Float
}

type Query {
  widgetA(id: ID!): Widget @stitch(key: "id")
}

# -- Location B

type Widget {
  id: ID!
  size: Float
}

type Query {
  widgetB(id: ID!): Widget @stitch(key: "id")
}

# -- Location C

type Widget {
  id: ID!
  name: String
  size: Float
}

type Query {
  featuredWidget: Widget
}
```

In this graph, `Widget` is a merged type without a resolver query in location C. This works because all of its fields are resolvable in other locations; that means location C can provide outbound representations of this type without ever needing to resolve inbound requests for it. Outbound types do still require a shared key field (such as `id` above) that allow them to join with data in other resolver locations (such as `price` above).