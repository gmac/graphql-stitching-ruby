## GraphQL::Stitching::Planner

A `Planner` generates a query plan for a given [`Supergraph`](./supergraph.md) and [`Request`](./request.md). The generated plan breaks down all the discrete GraphQL operations that must be delegated across locations and their sequencing.

```ruby
document = <<~GRAPHQL
  query MyQuery($id: ID!) {
    product(id:$id) {
      title
      brands { name }
    }
  }
GRAPHQL

request = GraphQL::Stitching::Request.new(
  supergraph,
  document,
  variables: { "id" => "1" },
  operation_name: "MyQuery",
).prepare!

plan = request.plan
```

### Caching

Plans are designed to be cacheable. This is very useful for redundant GraphQL documents (commonly sent by frontend clients) where there's no sense in planning every request individually. It's far more efficient to generate a plan once and cache it, then simply retreive the plan and execute it for future requests.

```ruby
cached_plan = $redis.get(request.digest)

plan = if cached_plan
  GraphQL::Stitching::Plan.from_json(JSON.parse(cached_plan))
else
  plan = request.plan

  $redis.set(request.digest, JSON.generate(plan.as_json))
  plan
end

# execute the plan...
```
