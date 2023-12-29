## GraphQL::Stitching::HttpExecutable

A `HttpExecutable` provides an out-of-the-box convenience for sending HTTP post requests to a remote location, or a base class for your own implementation with [GraphQL multipart uploads](https://github.com/jaydenseric/graphql-multipart-request-spec).

```ruby
exe = GraphQL::Stitching::HttpExecutable.new(
  url: "http://localhost:3001",
  headers: {
    "Authorization" => "..."
  }
)
```

### GraphQL file uploads

The [GraphQL Upload Spec](https://github.com/jaydenseric/graphql-multipart-request-spec) defines a multipart form structure for submitting GraphQL requests with file upload attachments. It's possible to pass these requests through stitched schemas using the following:

#### 1. Input file uploads as Tempfile variables

```ruby
client.execute(
  "mutation($file: Upload) { upload(file: $file) }",
  variables: { "file" => Tempfile.new(...) }
)
```

File uploads must enter the stitched schema as standard GraphQL variables with `Tempfile` values. The simplest way to recieve this input is to install [apollo_upload_server](https://github.com/jetruby/apollo_upload_server-ruby) into your stitching app's middleware so that multipart form submissions automatically unpack into standard variables.

#### 2. Enable `HttpExecutable.upload_types`

```ruby
client = GraphQL::Stitching::Client.new(locations: {
  alpha: {
    schema: GraphQL::Schema.from_definition(...),
    executable: GraphQL::Stitching::HttpExecutable.new(
      url: "http://localhost:3000",
      upload_types: ["Upload"], # << extract `Upload` scalars into multipart forms
    ),
  },
  bravo: {
    schema: GraphQL::Schema.from_definition(...),
    executable: GraphQL::Stitching::HttpExecutable.new(
      url: "http://localhost:3001"
    ),
  },
})
```

A location's `HttpExecutable` can then re-package `Tempfile` variables into multipart forms before sending them upstream. This is enabled with an `upload_types` parameter that specifies which scalar names require form extraction. Enabling `upload_types` does add some additional subgraph request processing, so it should only be enabled for locations that will actually recieve file uploads.

The upstream location will recieve a multipart form submission from stitching that can again be unpacked using [apollo_upload_server](https://github.com/jetruby/apollo_upload_server-ruby) or similar.
