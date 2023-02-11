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

# get the raw result without shaping
raw_result = GraphQL::Stitching::Executor.new(
  supergraph: supergraph,
  plan: plan.to_h,
  variables: variables,
).perform

# get the final result with shaping
final_result = GraphQL::Stitching::Executor.new(
  supergraph: supergraph,
  plan: plan.to_h,
  variables: variables,
).perform(document)
```

Note that an executor's `perform` method accepts a document argument. When provided, the raw execution result will be shaped for delivery to match the document. Without a document, the raw result will be returned with stitching inclusions and no null bubbling applied.
