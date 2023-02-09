## GraphQL::Stitching::Gateway

The `Gateway` is an out-of-the-box convenience with all stitching components assembled into a default workflow. A gateway is designed to work for most common needs, though you're welcome to assemble the component parts into your own configuration.

### Building

The Gateway constructor accepts configuration to build a [`Supergraph`](./supergraph.md) for you. Location names are root keys, and each location config provides a `schema` and an optional [executable](../README.md#executables).

```ruby
movies_schema = "type Query { ..."
showtimes_schema = "type Query { ..."

gateway = GraphQL::Stitching::Gateway.new(locations: {
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

### Execution

A gateway provides an `execute` method with a subset of arguments provided by [`GraphQL::Schema.execute`](https://graphql-ruby.org/queries/executing_queries). Executing requests to a stitched gateway becomes mostly a drop-in replacement to executing a `GraphQL::Schema` instance:

```ruby
result = gateway.execute(
  query: "query MyProduct($id: ID!) { product(id: $id) { name } }",
  variables: { "id" => "1" },
  operation_name: "MyProduct",
)
```

Arguments for the `execute` method include:

* `query`: a query (or mutation) as a string or parsed AST.
* `variables`: a hash of variables for the request.
* `operation_name`: the name of the operation to execute (when multiple are provided).
* `validate`: true if static validation should run on the supergraph schema before execution.
* `context`: an object that gets passed through to gateway caching and error hooks.

### Cache hooks

The gateway provides cache hooks to enable caching query plans across requests. Without caching, every request made the the gateway will be planned individually. With caching, a query may be planned once, cached, and then executed from cache for subsequent requests. Cache keys are a normalized digest of each query string.

```ruby
gateway.on_cache_read do |key, _context|
  $redis.get(key) # << 3P code
end

gateway.on_cache_write do |key, payload, _context|
  $redis.set(key, payload) # << 3P code
end
```

Note that inlined input data works against caching, so you should _avoid_ this:

```graphql
query {
  product(id: "1") { name }
}
```

Instead, always leverage variables in queries so that the document body remains consistent across requests:

```graphql
query($id: ID!) {
  product(id: $id) { name }
}

# variables: { "id" => "1" }
```

### Error hooks

The gateway also provides an error hook. Any program errors rescued during execution will be passed to the `on_error` handler, which can report on the error as needed and return a formatted error message for the gateway to add to the [GraphQL errors](https://spec.graphql.org/June2018/#sec-Errors) result.

```ruby
gateway.on_error do |err, context|
  # log the error
  Bugsnag.notify(err)

  # return a formatted message for the public response
  "Whoops, please contact support abount request '#{context[:request_id]}'"
end
```
