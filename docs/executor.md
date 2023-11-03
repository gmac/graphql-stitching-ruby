## GraphQL::Stitching::Executor

An `Executor` accepts a [`Supergraph`](./supergraph.md), a [query plan hash](./planner.md), and optional request variables. It handles executing requests and merging results collected from across graph locations.

```ruby
query = <<~GRAPHQL
  query MyQuery($id: ID!) {
    product(id:$id) {
      title
      brands { name }
    }
  }
GRAPHQL

request = GraphQL::Stitching::Request.new(
  query,
  variables: { "id" => "123" },
  operation_name: "MyQuery",
)

plan = GraphQL::Stitching::Planner.new(
  supergraph: supergraph,
  request: request,
).perform

result = GraphQL::Stitching::Executor.new(
  supergraph: supergraph,
  request: request,
  plan: plan.to_h,
).perform
```

### Raw results

By default, execution results are always returned with document shaping (stitching additions removed, missing fields added, null bubbling applied). You may access the raw execution result by calling the `perform` method with a `raw: true` argument:

```ruby
# get the raw result without shaping
raw_result = GraphQL::Stitching::Executor.new(
  supergraph: supergraph,
  request: request,
  plan: plan.to_h,
).perform(raw: true)
```

The raw result will contain many irregularities from the stitching process, however may be insightful when debugging inconsistencies in results:

```ruby
{
  "data" => {
    "product" => {
      "upc" => "1",
      "_export_upc" => "1",
      "_export_typename" => "Product",
      "name" => "iPhone",
      "price" => nil,
    }
  }
}
```

### Batching

The Executor batches together as many requests as possible to a given location at a given time. Batched queries are written with the operation name suffixed by all operation keys in the batch, and root stitching fields are each prefixed by their batch index and collection index (for non-list fields):

```graphql
query MyOperation_2_3($lang:String!,$currency:Currency!){
  _0_result: storefronts(ids:["7","8"]) { name(lang:$lang) }
  _1_0_result: product(upc:"abc") { price(currency:$currency) }
  _1_1_result: product(upc:"xyz") { price(currency:$currency) }
}
```

All told, the executor will make one request per location per generation of data. Generations started on separate forks of the resolution tree will be resolved independently.
