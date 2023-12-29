## GraphQL::Stitching::Request

A `Request` contains a parsed GraphQL document and variables, and handles the logistics of extracting the appropriate operation, variable definitions, and fragments. A `Request` should be built once per server request and passed through to other stitching components that utilize request information.

```ruby
source = "query FetchMovie($id: ID!) { movie(id:$id) { id genre } }"
request = GraphQL::Stitching::Request.new(
  supergraph,
  source,
  variables: { "id" => "1" },
  operation_name: "FetchMovie",
  context: { ... },
)
```

A `Request` provides the following information:

- `req.document`: parsed AST of the GraphQL source
- `req.variables`: a hash of user-submitted variables
- `req.string`: the original GraphQL source string, or printed document
- `req.digest`: a SHA2 of the request string
- `req.normalized_string`: printed document string with consistent whitespace
- `req.normalized_digest`: a SHA2 of the normalized string
- `req.operation`: the operation definition selected for the request
- `req.variable_definitions`: a mapping of variable names to their type definitions
- `req.fragment_definitions`: a mapping of fragment names to their fragment definitions

### Preparing requests

A request should be prepared for stitching using the `prepare!` method _after_ validations have been run:

```ruby
document = <<~GRAPHQL
  query FetchMovie($id: ID!, $lang: String = "en", $withShowtimes: Boolean = true) {
    movie(id:$id) {
      id
      title(lang: $lang)
      showtimes @include(if: $withShowtimes) {
        time
      }
    }
  }
GRAPHQL

request = GraphQL::Stitching::Request.new(
  supergraph,
  document,
  variables: { "id" => "1" },
  operation_name: "FetchMovie",
)

errors = MySchema.validate(request.document)
# return early with any static validation errors...

request.prepare!
```

Preparing a request will apply several destructive transformations:

- Default values from variable definitions will be added to request variables.
- The document will be pre-shaped based on `@skip` and `@include` directives.
