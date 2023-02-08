## GraphQL::Stitching::Gateway

The `Gateway` is an out-of-the-box convenience with all stitching components assembled into a default workflow. A gateway is designed to work for most common needs, though you're welcome to assemble the component parts into your own configuration.

### Building

The Gateway constructor accepts configuration to build a [`Supergraph`](./supergraph.md) for you. Location names are root keys, and each location config provides a `schema` and an optional [executable](../README.md#executables).

```ruby
movies_schema = "type Query { ..."
showtimes_schema = "type Query { ..."

gateway = GraphQL::Stitching::Gateway.new({
  products: {
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
```

Locations provided with only a `schema` will assign the schema as the location executable (these are locally-executable schemas, and must have locally-implemented resolvers). Locations that provide an `executable` will perform requests using the executable.

### Cache hooks

The gateway provides cache hooks to enable caching query plans across requests. Without caching, every request made the the gateway will be planned individually. With caching, a query may be planned once, cached, and then executed from cache for subsequent requests. Cache keys are a normalized digest of each query string.

```ruby
gateway.cache_read do |key|
  $redis.get(key) # << 3P code
end

gateway.cache_write do |key, payload|
  $redis.set(key, payload) # << 3P code
end
```

Note that inlined input data works against caching:

```graphql
query {
  product(id: "1") { name }
}
```

You should always leverage variables in queries so that the document body remains consistent across requests:

```graphql
query($id: ID!) {
  product(id: $id) { name }
}

# variables: { "id" => "1" }
```

### Execution

A gateway provides an `execute` method with a subset of arguments provided by [`GraphQL::Schema.execute`](https://graphql-ruby.org/queries/executing_queries). Executing requests to a stitched gateway becomes mostly a drop-in replacement to executing a `GraphQL::Schema` instance:

```ruby
result = gateway.execute(
  query: "query MyProduct($id: ID!) { product(id: $id) { name } }",
  variables: { "id" => "1" },
  operation_name: "MyProduct",
)
```

Execute arguments include:
* `query`: a query (or mutation) string.
* `document`: a pre-parsed AST. Either `query` or `document` are required.
* `operation_name`: the name of the operation to execute (when multiple are provided).
* `validate`: true if static validation should run on the supergraph schema before execution.
