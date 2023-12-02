## GraphQL::Stitching::Client

The `Client` is an out-of-the-box convenience with all stitching components assembled into a default workflow. A client is designed to work for most common needs, though you're welcome to assemble the component parts into your own configuration (see the [client source](../lib/graphql/stitching/client.rb) for an example). A client is constructed with the same [location settings](./composer.md#performing-composition) used to perform supergraph composition:

```ruby
movies_schema = "type Query { ..."
showtimes_schema = "type Query { ..."

client = GraphQL::Stitching::Client.new(locations: {
  products: {
    schema: GraphQL::Schema.from_definition(movies_schema),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3000"),
    stitch: [{ field_name: "products", key: "id" }],
  },
  showtimes: {
    schema: GraphQL::Schema.from_definition(showtimes_schema),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001"),
  },
  my_local: {
    schema: MyLocal::GraphQL::Schema,
  },
})
```

Alternatively, you may pass a prebuilt `Supergraph` instance to the `Client` constructor. This is useful when [exporting and rehydrating](./supergraph.md#export-and-caching) supergraph instances, which bypasses the need for runtime composition:

```ruby
supergraph_sdl = File.read("precomposed_schema.graphql")
supergraph = GraphQL::Stitching::Supergraph.from_definition(
  supergraph_sdl,
  executables: { ... },
)

client = GraphQL::Stitching::Client.new(supergraph: supergraph)
```

### Execution

A client provides an `execute` method with a subset of arguments provided by [`GraphQL::Schema.execute`](https://graphql-ruby.org/queries/executing_queries). Executing requests on a stitching client becomes mostly a drop-in replacement to executing on a `GraphQL::Schema` instance:

```ruby
result = client.execute(
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
* `context`: an object passed through to executable calls and client hooks.

### Cache hooks

The client provides cache hooks to enable caching query plans across requests. Without caching, every request made to the client will be planned individually. With caching, a query may be planned once, cached, and then executed from cache for subsequent requests. Cache keys are a normalized digest of each query string.

```ruby
client.on_cache_read do |request|
  $redis.get(request.digest) # << 3P code
end

client.on_cache_write do |request, payload|
  $redis.set(request.digest, payload) # << 3P code
end
```

Note that inlined input data works against caching, so you should _avoid_ these input literals when possible:

```graphql
query {
  product(id: "1") { name }
}
```

Instead, leverage query variables so that the document body remains consistent across requests:

```graphql
query($id: ID!) {
  product(id: $id) { name }
}

# variables: { "id" => "1" }
```

### Error hooks

The client also provides an error hook. Any program errors rescued during execution will be passed to the `on_error` handler, which can report on the error as needed and return a formatted error message for the client to add to the [GraphQL errors](https://spec.graphql.org/June2018/#sec-Errors) result.

```ruby
client.on_error do |request, err|
  # log the error
  Bugsnag.notify(err)

  # return a formatted message for the public response
  "Whoops, please contact support abount request '#{request.context[:request_id]}'"
end
```
