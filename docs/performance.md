## Performance

There are many considerations that can aid in the performance of a stitched schema.

### Batching

The stitching executor automatically batches subgraph requests so that only one request is made per location per generation of data (multiple generations can still force the executor to return to a location for more data). This is done using batched queries that combine all data access for a given a location. For example:

```graphql
query MyOperation_2($_0_key:[ID!]!, $_1_0_key:ID!, $_1_1_key:ID!, $_1_2_key:ID!) {
  _0_result: widgets(ids: $_0_key) { ... } # << 3 Widget
  _1_0_result: sprocket(id: $_1_0_key) { ... } # << 1 Sprocket
  _1_1_result: sprocket(id: $_1_1_key) { ... } # << 1 Sprocket
  _1_2_result: sprocket(id: $_1_2_key) { ... } # << 1 Sprocket
}
```

You can make optimal use of this batching behavior by following some best-practices:

1. List queries (like the `widgets` selection above) are preferable as resolver queries because they keep the batched document consistent regardless of set size, and make for smaller documents that parse and validate faster.

2. Root subgraph fields used as merged type resolvers (like the three `sprocket` selections above) should implement [batch loading](https://github.com/Shopify/graphql-batch) to anticipate repeated selections. Never assume that a root field will only be selected once per request.

### Query plan caching

A stitching client provides caching hooks for saving query plans. Without caching, every request made to the client will be planned individually. With caching, a query may be planned once, cached, and then executed from cache on subsequent requests. The provided `request` object includes digests for use in cache keys:

```ruby
client = GraphQL::Stitching::Client.new(locations: { ... })

client.on_cache_read do |request|
  # get a cached query plan...
  $cache.get(request.digest)
end

client.on_cache_write do |request, payload|
  # write a computed query plan...
  $cache.set(request.digest, payload)
end
```

Note that inlined input data (such as the `id: "1"` argument below) works against caching, so you should _avoid_ these input literals when possible:

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

### Subgraph validations

Requests are validated by the supergraph, and should always divide into valid subgraph documents. Therefore, you can skip redundant subgraph validations for requests sent by the supergraph, ex:

```ruby
exe = GraphQL::Stitching::HttpExecutable.new(
  url: "http://localhost:3001",
  headers: { 
    "Authorization" => "...",
    "X-Supergraph-Secret" => "<shared-secret>",
  },
)
```

A shared secret allows a subgraph location to trust the supergraph origin, at which time it can disable validations:

```ruby
def query
  sg_header = request.headers["X-Supergraph-Secret"]
  MySchema.execute(
    query: params[:query],
    variables: params[:variables],
    operation_name: params[:operationName],
    validate: sg_header.nil? || sg_header != Rails.env.credentials.supergraph,
  )
end
```

### Digests

All computed digests use SHA2 hashing by default. You can swap in [a faster algorithm](https://github.com/Shopify/blake3-rb) and/or add base state by reconfiguring `Stitching.digest`:

_config/initializers/graphql_stitching.rb_
```ruby
GraphQL::Stitching.digest { |str| Digest::Blake3.hexdigest("v2/#{str}") }
```

### Concurrency

The stitching executor builds atop the Ruby fiber-based implementation of `GraphQL::Dataloader`. Non-blocking concurrency requires setting a fiber scheduler via `Fiber.set_scheduler`, see [graphql-ruby docs](https://graphql-ruby.org/dataloader/nonblocking.html). You may also need to build your own remote clients using corresponding HTTP libraries.
