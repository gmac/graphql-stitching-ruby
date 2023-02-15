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

request = GraphQL::Stitching::Request.new(query, variables: { "id" => "123" }, operation_name: "MyQuery")

plan = GraphQL::Stitching::Planner.new(
  supergraph: supergraph,
  request: request,
).perform

result = GraphQL::Stitching::Executor.new(
  supergraph: supergraph,
  plan: plan.to_h,
  request: request,
).perform
```

### Raw results

By default, execution results are always returned with document shaping (stitching additions removed, missing fields added, null bubbling applied). You may access the raw execution result by calling the `perform` method with a `raw: true` argument:

```ruby
# get the raw result without shaping
raw_result = GraphQL::Stitching::Executor.new(
  supergraph: supergraph,
  plan: plan.to_h,
  request: request,
).perform(raw: true)
```
