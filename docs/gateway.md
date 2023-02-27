## GraphQL::Stitching::Gateway

The `Gateway` is an out-of-the-box convenience with all stitching components assembled into a default workflow. A gateway is designed to work for most common needs, though you're welcome to assemble the component parts into your own configuration. A Gateway is constructed with the same [location settings](./composer.md#performing-composition) used to perform supergraph composition:

```ruby
movies_schema = "type Query { ..."
showtimes_schema = "type Query { ..."

gateway = GraphQL::Stitching::Gateway.new(locations: {
  products: {
    schema: GraphQL::Schema.from_definition(movies_schema),
    executable: GraphQL::Stitching::RemoteClient.new(url: "http://localhost:3000"),
    stitch: [{ field_name: "products", key: "id" }],
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

Alternatively, you may pass a prebuilt `Supergraph` instance to the Gateway constructor. This is useful when [exporting and rehydrating](./supergraph.md#export-and-caching) supergraph instances, which bypasses the need for runtime composition:

```ruby
exported_schema = "type Query { ..."
exported_mapping = JSON.parse("{ ... }")
supergraph = GraphQL::Stitching::Supergraph.from_export(
  schema: exported_schema,
  delegation_map: exported_mapping,
  executables: { ... },
)

gateway = GraphQL::Stitching::Gateway.new(supergraph: supergraph)
```

### Execution

A gateway provides an `execute` method with a subset of arguments provided by [`GraphQL::Schema.execute`](https://graphql-ruby.org/queries/executing_queries). Executing requests on a stitched gateway becomes mostly a drop-in replacement to executing on a `GraphQL::Schema` instance:

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
* `context`: an object passed through to executable calls and gateway hooks.

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
