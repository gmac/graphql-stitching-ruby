## Executables

An executable resource performs location-specific GraphQL requests. Executables may be `GraphQL::Schema` classes, or any object that responds to `.call(request, source, variables)` and returns a raw GraphQL response:

```ruby
class MyExecutable
  def call(request, source, variables)
    # process a GraphQL request...
    return {
      "data" => { ... },
      "errors" => [ ... ],
    }
  end
end
```

A supergraph is composed with executable resources provided for each location. Any location that omits the `executable` option will use the provided `schema` as its default executable:

```ruby
client = GraphQL::Stitching::Client.new(locations: {
  first: {
    schema: FirstSchema,
    # executable:^^^^^^ delegates to FirstSchema,
  },
  second: {
    schema: SecondSchema,
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001", headers: { ... }),
  },
  third: {
    schema: ThirdSchema,
    executable: MyExecutable.new,
  },
  fourth: {
    schema: FourthSchema,
    executable: ->(req, query, vars) { ... },
  },
})
```

## HttpExecutable

The `GraphQL::Stitching` library provides one default executable: `HttpExecutable`. This is an out-of-the-box convenience for sending HTTP post requests to a remote location, or a base class for your own implementation with [file uploads](#file-uploads).

```ruby
executable = GraphQL::Stitching::HttpExecutable.new(
  url: "http://localhost:3001",
  headers: { "Authorization" => "..." },
  upload_types: #...
)
```

- **`url:`**, the URL of an endpoint to post GraphQL requests to.
- **`headers:`**, a hash of headers to encode into post requests.
- **`upload_types:`**, an array of scalar names to process as [file uploads](#file-uploads), see below.

Extend this class to reimplement HTTP transmit behaviors using your own libraries. Specifically, override the following methods:

- **`send(request, document, variables)`**, transmits a basic HTTP request.
- **`send_multipart_form(request, form_data)`**, transmits multipart form data.

### The `Stitching::Request` object

HttpExecutable methods recieve the supergraph's `request` object, which contains all information about the supergraph request being processed. This includes useful caching information:

- `req.variables`: a hash of user-submitted variables.
- `req.original_document`: the original validated request document, before skip/include.
- `req.string`: the prepared GraphQL source string being executed, after skip/include.
- `req.digest`: digest of the prepared string, hashed by the [`Stitching.digest`](./performance.md#digests) implementation.
- `req.normalized_string`: printed source string with consistent whitespace.
- `req.normalized_digest`: a digest of the normalized string, hashed by the [`Stitching.digest`](./performance.md#digests) implementation.
- `req.operation`: the operation definition selected for the request.
- `req.variable_definitions`: a mapping of variable names to their type definitions.
- `req.fragment_definitions`: a mapping of fragment names to their fragment definitions.

## File uploads

The [GraphQL upload spec](https://github.com/jaydenseric/graphql-multipart-request-spec) defines a multipart form structure for submitting GraphQL requests with file upload attachments. These can proxy through a supergraph with the following steps:

### 1. Input file uploads as Tempfile variables

```ruby
client.execute(
  "mutation($file: Upload) { upload(file: $file) }",
  variables: { "file" => Tempfile.new(...) }
)
```

File uploads must enter the supergraph as standard GraphQL variables with `Tempfile` values cast as a dedicated upload scalar type. The simplest way to recieve this input is to install [apollo_upload_server](https://github.com/jetruby/apollo_upload_server-ruby) into your app's middleware so that multipart form submissions automatically unpack into tempfile variables.

### 2. Enable `HttpExecutable.upload_types`

```ruby
client = GraphQL::Stitching::Client.new(locations: {
  alpha: {
    schema: GraphQL::Schema.from_definition(...),
    executable: GraphQL::Stitching::HttpExecutable.new(
      url: "http://localhost:3001",
      upload_types: ["Upload"], # << extract `Upload` scalars into multipart forms
    ),
  },
  bravo: {
    schema: GraphQL::Schema.from_definition(...),
    executable: GraphQL::Stitching::HttpExecutable.new(
      url: "http://localhost:3002",
    ),
  },
})
```

A location's `HttpExecutable` can then re-package `Tempfile` variables into multipart forms before sending them upstream. This is enabled with an `upload_types` parameter that specifies what scalar names require form extraction. Enabling `upload_types` adds some additional subgraph request processing, so it should only be enabled for locations that will actually recieve file uploads.

The upstream location will recieve a multipart form submission from the supergraph that can again be unpacked using [apollo_upload_server](https://github.com/jetruby/apollo_upload_server-ruby) or similar.
