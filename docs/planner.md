## GraphQL::Stitching::Planner

A `Planner` generates a query plan for a given [`Supergraph`](./supergraph.md) and request [`Document`](./document.md). The generated plan breaks down all the discrete GraphQL operations that must be delegated across locations and their sequencing.

```ruby
request = <<~GRAPHQL
  query MyQuery($id: ID!) {
    product(id:$id) {
      title
      brands { name }
    }
  }
GRAPHQL

document = GraphQL::Stitching::Document.new(request, operation_name: "MyQuery")

plan = GraphQL::Stitching::Planner.new(
  supergraph: supergraph,
  document: document,
).perform
```

### Caching

Plans are designed to be cacheable. This is very useful for redundant GraphQL documents (commonly sent by frontend clients) where there's no sense in planning every request individually. It's far more efficient to generate a plan once and cache it, then simply retreive the plan and execute it for future requests.

```ruby
cached_plan = $redis.get(document.digest)

plan = if cached_plan
  JSON.parse(cached_plan)
else
  plan_hash = GraphQL::Stitching::Planner.new(
    supergraph: supergraph,
    document: document,
  ).perform.to_h

  $redis.set(document.digest, JSON.generate(plan_hash))
  plan_hash
end

# execute the plan...
```
