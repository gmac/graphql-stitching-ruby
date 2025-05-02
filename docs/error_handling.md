## Error handling

Failed stitching requests can be tricky to debug because it's not always obvious where the actual error occured. Error handling helps surface issues and make them easier to locate.

### Supergraph errors

When exceptions happen while executing requests within the stitching layer, they will be rescued by the stitching client and trigger an `on_error` hook. You should add your stack's error reporting here and return a formatted error message to appear in [GraphQL errors](https://spec.graphql.org/June2018/#sec-Errors) for the request.

```ruby
client = GraphQL::Stitching::Client.new(locations: { ... })
client.on_error do |request, err|
  # log the error
  Bugsnag.notify(err)

  # return a formatted message for the public response
  "Whoops, please contact support abount request '#{request.context[:request_id]}'"
end

# Result:
# { "errors" => [{ "message" => "Whoops, please contact support abount request '12345'" }] }
```

### Subgraph errors

When subgraph resources produce errors, it's very important that each error provides a proper `path` indicating the field associated with the error. Most major GraphQL implementations, including GraphQL Ruby, [do this automatically](https://graphql-ruby.org/errors/overview.html):

```json
{
  "data": { "shop": { "product": null } },
  "errors": [{
    "message": "Record not found.",
    "path": ["shop", "product"]
  }]
}
```

Be careful when resolving lists, particularly for merged type resolvers. Lists should only error out specific array positions rather than the entire array result whenever possible, for example:

```ruby
def products
  [
    { id: "1" },
    GraphQL::ExecutionError.new("Not found"),
    { id: "3" },
  ]
end
```

These cases should report corresponding errors pathed down to the list index without affecting other successful results in the list:

```json
{
  "data": {
    "products": [{ "id": "1" }, null, { "id": "3" }]
  },
  "errors": [{
    "message": "Record not found.",
    "path": ["products", 1]
  }]
}
```

### Merging subgraph errors

All [spec GraphQL errors](https://spec.graphql.org/June2018/#sec-Errors) returned from subgraph queries will flow through the stitched request and into the final result. Formatting these errors follows one of two strategies:

1. **Direct passthrough**, where subgraph errors are returned directly in the merged response without modification. This strategy is used for errors without a `path` (ie: "base" errors), and errors pathed to root fields.

2. **Mapped passthrough**, where the `path` attribute of a subgraph error is remapped to an insertion point in the supergraph request. This strategy is used when a merged type resolver returns an error for an object in a lower-level position of the supergraph document.
