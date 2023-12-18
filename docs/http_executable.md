## GraphQL::Stitching::HttpExecutable

A `HttpExecutable` provides an out-of-the-box convenience for sending HTTP post requests to a remote location, or a base class for your own implementation with [GraphQL multipart uploads](https://github.com/jaydenseric/graphql-multipart-request-spec?tab=readme-ov-file#multipart-form-field-structure).

```ruby
exe = GraphQL::Stitching::HttpExecutable.new(
  url: "http://localhost:3001",
  headers: {
    "Authorization" => "..."
  }
)
```

### GraphQL Uploads via multipart forms

The [GraphQL Upload Spec](https://github.com/jaydenseric/graphql-multipart-request-spec) defines a multipart form structure for submitting GraphQL requests that include file upload attachments. It is possible to flow these requests through a stitched schema using the following steps:

1. File uploads must be submitted to stitching as basic GraphQL variables with `Tempfile` values assigned. The simplest way to recieve this input is to install [apollo_upload_server](https://github.com/jetruby/apollo_upload_server-ruby) into your stitching app's middleware so that multipart form submissions arrive unpackaged and in the expected format.

```ruby
client.execute(
  "mutation($file: Upload) { upload(file: $file) }",
  variables: { "file" => Tempfile.new(...) }
)
```

2. Stitching will route the request and its variables as normal. Then it's up to `HttpExecutable` to re-package any upload variables into the multipart form spec before sending them upstream. This is enabled with an `upload_types` parameter to tell the executable what scalar names must be extracted:

```ruby

client = GraphQL::Stitching::Client.new(locations: {
  products: {
    schema: GraphQL::Schema.from_definition(...),
    executable: GraphQL::Stitching::HttpExecutable.new(
      url: "http://localhost:3000",
      upload_types: ["Upload"], # << extract "Upload" scalars into multipart forms
    ),
  },
  showtimes: {
    schema: GraphQL::Schema.from_definition(...),
    executable: GraphQL::Stitching::HttpExecutable.new(
      url: "http://localhost:3001"
    ),
  },
})
```

Note that `upload_types` adds request processing, so it should only be enabled for locations that actually recieve file uploads. Those locations can again leverage [apollo_upload_server](https://github.com/jetruby/apollo_upload_server-ruby) to unpack the multipart form sent by stitching.
