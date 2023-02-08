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

variables = { "id" => "123" }

document = GraphQL::Stitching::Document.new(query, operation_name: "MyQuery")

plan = GraphQL::Stitching::Planner.new(
  supergraph: supergraph,
  document: document,
).perform

raw_result = GraphQL::Stitching::Executor.new(
  supergraph: supergraph,
  plan: plan.to_h,
  variables: variables,
).perform
```

The executor returns a raw result of data collected and merged from across locations. This includes stitching keys and may have nullability violations. This view of the data may still be useful for debugging. Run the raw result through the `Shaper` for final output:

```ruby
final_result = GraphQL::Stitching::Shaper.perform(
  supergraph: supergraph,
  document: document,
  raw: raw_result,
)
```
