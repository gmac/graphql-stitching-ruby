## GraphQL::Stitching::Planner

A `Planner` generates a query plan for a given [`Supergraph`](./supergraph.md) and [`Document`](./document.md). The generated plan breaks down all the discrete operations that must be delegated across locations and their sequencing.

```ruby
plan = GraphQL::Stitching::Planner.new(
  supergraph: supergraph,
  document: document,
).perform.to_h
```

Plans are designed to be cacheable. For redundant GraphQL documents (commonly coming from a frontend client), there's no sense in planning every request individually. It's far more efficient to generate a plan once and stash it in a key/value store, then simply retreive the plan and execute it each time a request matches it.
