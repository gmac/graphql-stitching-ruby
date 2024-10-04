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

- `req.document`: parsed AST of the GraphQL source.
- `req.variables`: a hash of user-submitted variables.
- `req.string`: the original GraphQL source string, or printed document.
- `req.digest`: a digest of the request string, hashed by the `Stitching.digest` implementation.
- `req.normalized_string`: printed document string with consistent whitespace.
- `req.normalized_digest`: a digest of the normalized string, hashed by the `Stitching.digest` implementation.
- `req.operation`: the operation definition selected for the request.
- `req.variable_definitions`: a mapping of variable names to their type definitions.
- `req.fragment_definitions`: a mapping of fragment names to their fragment definitions.

### Request lifecycle

A request manages the flow of stitching behaviors. These are sequenced by the `Client`
component, or you may invoke them manually:

1. `request.validate`: runs static validations on the request using the combined schema.
2. `request.prepare!`: inserts variable defaults and pre-renders skip/include conditional shaping.
3. `request.plan`: builds a plan for the request. May act as a setter for plans pulled from cache.
4. `request.execute`: executes the request, and returns the resulting data.
