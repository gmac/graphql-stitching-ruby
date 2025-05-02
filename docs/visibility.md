# Visibility

Visibility controls can hide parts of a supergraph from select audiences without compromising stitching operations. Restricted schema elements are hidden from introspection and validate as though they do not exist (which is different from traditional authorization where an element is acknowledged as restricted). Visibility is useful for managing multiple distributions of a schema for different audiences, and provides a flexible analog to Apollo Federation's `@inaccessible` rule.

Under the hood, this system wraps [GraphQL visibility](https://graphql-ruby.org/authorization/visibility) (specifically, the newer `GraphQL::Schema::Visibility` with nil profile support) and requires at least GraphQL Ruby v2.5.3.

## Example

Schemas may include a `@visibility` directive that defines element _profiles_. A profile is just a label describing an API distribution (public, private, etc). When a request is assigned a visibility profile, it can only access elements belonging to that profile. Elements without an explicit `@visibility` constraint belong to all profiles. For example:

_schemas/product_info.graphql_
```graphql
directive @stitch(key: String!) on FIELD_DEFINITION
directive @visibility(profiles: [String!]!) on OBJECT | INTERFACE | UNION | INPUT_OBJECT | ENUM | SCALAR | FIELD_DEFINITION | ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION | ENUM_VALUE

type Product {
  id: ID!
  title: String!
  description: String!
}

type Query {
  featuredProduct: Product
  product(id: ID!): Product @stitch(key: "id") @visibility(profiles: ["private"])
}
```

_schemas/product_prices.graphql_
```graphql
directive @stitch(key: String!) on FIELD_DEFINITION
directive @visibility(profiles: [String!]!) on OBJECT | INTERFACE | UNION | INPUT_OBJECT | ENUM | SCALAR | FIELD_DEFINITION | ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION | ENUM_VALUE

type Product {
  id: ID! @visibility(profiles: [])
  msrp: Float! @visibility(profiles: ["private"])
  price: Float!
}

type Query {
  products(ids: [ID!]!): [Product]! @stitch(key: "id") @visibility(profiles: ["private"])
}
```

When composing a stitching client, the names of all possible visibility profiles that the supergraph should respond to are specified in composer options:

```ruby
client = GraphQL::Stitching::Client.new(
  composer_options: {
    visibility_profiles: ["public", "private"],
  },
  locations: {
    info: {
      schema: GraphQL::Schema.from_definition(File.read("schemas/product_info.graphql")),
      executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001"),
    },
    prices: {
      schema: GraphQL::Schema.from_definition(File.read("schemas/product_prices.graphql")),
      executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3002"),
    },
  }
)
```

The client can then execute requests with a `visibility_profile` parameter in context that specifies one of these names:

```ruby
query = %|{
  featuredProduct {
    title  # always visible
    price  # always visible
    msrp   # only visible to "private" or without profile
    id     # only visible without profile
  }
}|

result = client.execute(query, context: { 
  visibility_profile: "public", # << or "private"
})
```

The `visibility_profile` parameter will select which visibility distribution to use while introspecting and validating the request. For example:

- Using `visibility_profile: "public"` will say the `msrp` field does not exist (because it is restricted to "private").
- Using `visibility_profile: "private"` will accesses the `msrp` field as usual. 
- Providing no profile parameter (or `visibility_profile: nil`) will access the entire graph without any visibility constraints.

The full potential of visibility comes when hiding stitching implementation details, such as the `id` field (which is the stitching key for the Product type). While the `id` field is hidden from all named profiles, it remains operational for use by the stitching implementation.

## Adding visibility directives

Add the `@visibility` directive into schemas using the library definition:

```ruby
class QueryType < GraphQL::Schema::Object
  field :my_field, String, null: true do |f|
    f.directive(GraphQL::Stitching::Directives::Visibility, profiles: ["private"])
  end
end

class MySchema < GraphQL::Schema
  directive(GraphQL::Stitching::Directives::Visibility)
  query(QueryType)
end
```

## Merging visibilities

Visibility directives merge across schemas into the narrowest constraint possible. Profiles for an element will intersect into its merged supergraph constraint:

```graphql
# location 1
myField: String @visibility(profiles: ["a", "c"])

# location 2
myField: String @visibility(profiles: ["b", "c"])

# merged supergraph
myField: String @visibility(profiles: ["c"])
```

This may cause an element's profiles to intersect into an empty set, which means the element belongs to no profiles and will be hidden from all named distributions:

```graphql
# location 1
myField: String @visibility(profiles: ["a"])

# location 2
myField: String @visibility(profiles: ["b"])

# merged supergraph
myField: String @visibility(profiles: [])
```

Locations may omit visibility information to give other locations full control. Remember that elements without a `@visibility` constraint belong to all profiles, which also applies while merging:

```graphql
# location 1
myField: String

# location 2
myField: String @visibility(profiles: ["b"])

# merged supergraph
myField: String @visibility(profiles: ["b"])
```

## Type controls

Visibility controls can be applied to almost all GraphQL schema elements, including:

- Types (Object, Interface, Union, Enum, Scalar, InputObject)
- Fields (of Object and Interface)
- Arguments (of Field and InputObject)
- Enum values

While the visibility of type members (fields, arguments, and enum values) are pretty intuitive, the visibility of parent types is far more nuanced as constraints start to cascade:

```graphql
type Widget @visibility(profiles: ["private"]) {
  title: String
}

type Query {
  widget: Widget # << GETS HIDDEN
}
```

In this example, hiding the `Widget` type will also hide the `Query.widget` field that returns it. You can review materialized visibility profiles by printing their respective schemas:

```ruby
public_schema = client.supergraph.to_definition(visibility_profile: "public")
File.write("schemas/supergraph_public.graphql", public_schema)

private_schema = client.supergraph.to_definition(visibility_profile: "private")
File.write("schemas/supergraph_private.graphql", private_schema)
```

It's helpful to commit these outputs to your repo where you can monitor their diffs during the PR process.
