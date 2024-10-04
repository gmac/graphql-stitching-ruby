## Schema Stitching, mechanics

### Modeling foreign keys for stitching

Foreign keys in a GraphQL schema typically look like the `Product.imageId` field here:

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

However, this design does not lend itself to stitching where types need to _merge_ across locations. A simple schema refactor makes this foreign key more expressive as an entity type, and turns the key into an _object_ that will merge with analogous object types in other locations:

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

### Deploying a stitched schema

Among the simplest and most effective ways to manage a stitched schema is to compose it locally, write the composed SDL as a `.graphql` file in your repo, and then load the composed schema into a stitching client at runtime. For example, setup a `rake` task that loads/fetches subgraph schemas, composes them, and then writes the composed schema definition as a file committed to the repo:

```ruby
task :compose_graphql do
  schema1_sdl = ... # load schema 1
  schema2_sdl = ... # load schema 2

  supergraph = GraphQL::Stitching::Composer.new.perform({
    schema1: {
      schema: GraphQL::Schema.from_definition(schema1_sdl)
    },
    schema2: {
      schema: GraphQL::Schema.from_definition(schema2_sdl)
    }
  })

  File.write("schema/supergraph.graphql", supergraph.to_definition)
  puts "Schema composition was successful."
end

# bundle exec rake compose-graphql
```

Then at runtime, load the composed schema into a stitching client:

```ruby
class GraphQlController
  class < self
    def client
      @client ||= begin
        supergraph_sdl = File.read("schema/supergraph.graphql")
        supergraph = GraphQL::Stitching::Supergraph.from_definition(supergraph_sdl, executables: {
          schema1: GraphQL::Stitching::HttpExecutable.new("http://localhost:3001/graphql"),
          schema2: GraphQL::Stitching::HttpExecutable.new("http://localhost:3002/graphql"),
        })
        GraphQL::Stitching::Client.new(supergraph: supergraph)
      end
    end
  end

  def exec
    self.class.client.execute(
      params[:query],
      variables: params[:variables],
      operation_name: params[:operation_name]
    )
  end
end
```

This process assures that composition always happens before deployment where failures can be detected. Use CI to verify that the repo's supergraph output is always up to date. Hot reloading of the supergraph can also be accommodated by uploading the composed schema to a sync location (cloud storage, etc) that is polled by the application runtime. When the schema changes, load it into a new stitching client and swap that into the application.

### Field selection routing

Fields of a merged type may exist in multiple locations. For example, the `title` field below is provided by both locations:

```graphql
# -- Location A

type Movie {
  id: String!
  title: String! # shared
  rating: Int!
}

type Query {
  movieA(id: ID!): Movie @stitch(key: "id")
}

# -- Location B

type Movie {
  id: String!
  title: String! # shared
  reviews: [String!]!
}

type Query {
  movieB(id: ID!): Movie @stitch(key: "id")
}
```

When planning a request, field selections always attempt to use the current routing location that originates from the selection root, for example:

```graphql
query GetTitleFromA {
  movieA(id: "23") { # <- enter via Location A
    title            # <- source from Location A
  }
}

query GetTitleFromB {
  movieB(id: "23") { # <- enter via Location B
    title            # <- source from Location B
  }
}
```

Field selections that are NOT available in the current routing location delegate to new locations as follows:

1. Fields with only one location automatically use that location.
2. Fields with multiple locations attempt to use a location added during step-1.
3. Any remaining fields pick a location based on their highest availability among locations.

### Root selection routing

Root fields should route to the primary locations of their provided types. This assures that the most common data for a type can be resolved via root access and thus avoid unnecessary stitching. Root fields can select their primary locations using the `root_field_location_selector` option in [composer configuration](./composer.md#configuring-composition):

```ruby
supergraph = GraphQL::Stitching::Composer.new(
  root_field_location_selector: ->(locations) { locations.find { _1 == "a" } || locations.last },
).perform({ ... })
```

It's okay if root field names are repeated across locations. The primary location will be used when routing root selections:

```graphql
# -- Location A

type Movie {
  id: String!
  rating: Int!
}

type Query {
  movie(id: ID!): Movie @stitch(key: "id") # shared, primary
}

# -- Location B

type Movie {
  id: String!
  reviews: [String!]!
}

type Query {
  movie(id: ID!): Movie @stitch(key: "id") # shared
}

# -- Request

query {
  movie(id: "23") { id } # routes to Location A
}
```

Note that primary location routing _only_ applies to selections in the root scope. If the `Query` type appears again lower in the graph, then its fields are resolved as normal object fields outside of root context, for example:

```graphql
schema {
  query: Query # << root query, uses primary locations
}

type Query {
  subquery: Query # << subquery, acts as a normal object type
}
```

Also note that stitching queries (denoted by the `@stitch` directive) are completely separate from field routing concerns. A `@stitch` directive establishes a contract for resolving a given type in a given location. This contract is always used to collect stitching data, regardless of how request routing selected the location for use.

### Stitched errors

Any [spec GraphQL errors](https://spec.graphql.org/June2018/#sec-Errors) returned by a stitching query will flow through the request. Stitching has two strategies for passing errors through to the final result:

1. **Direct passthrough**, where subgraph errors are returned directly without modification. This strategy is used for errors without a `path` (ie: "base" errors), and errors pathed to root fields.

2. **Mapped passthrough**, where the `path` attribute of a subgraph error is remapped to an insertion point in the stitched request. This strategy is used when merging stitching queries into the composed result.

In either strategy, it's important that subgraphs provide properly pathed errors (GraphQL Ruby [can do this automatically](https://graphql-ruby.org/errors/overview.html)). For example:

```json
{
  "data": { "shop": { "product": null } },
  "errors": [{
    "message": "Record not found.",
    "path": ["shop", "product"]
  }]
}
```

When resolving [stitching list queries](../README.md#list-queries), it's important to only error out specific array positions rather than the entire array result, for example:

```ruby
def products
  [
    { id: "1" },
    GraphQL::ExecutionError.new("Not found"),
    { id: "3" },
  ]
end
```

Stitching expects list queries to pad their missing elements with null, and to report corresponding errors pathed down to list position:

```json
{
  "data": {
    "products": [{ "id": "1" }, null, { "id": "3" }]
  },
  "errors": [{
    "message": "Record not found.",
    "path": ["products", 1]
  }]
}
```

### Null results

It's okay for a stitching query to return `null` for a merged type as long as all unique fields of the type allow null. For example, the following merge works:

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

Location B is allowed to return `null` here because its one unique field, `rating`, is nullable (the `id` field can be provided by Location A). If `rating` were non-null, then null bubbling would invalidate the response data.

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

In this graph, `Widget` is a merged type without a resolver query in location C. This works because all of its fields are resolvable in other locations; that means location C can provide outbound representations of this type without ever needing to resolve inbound requests for it. Outbound types do still require a shared key field (such as `id` above) that allow them to join with data in other resolver locations (such as `price` above). Support for this pattern is limited to single-field keys, [composite keys](../README.md#composite-type-keys) require a resolver definition.
