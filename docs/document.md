## GraphQL::Stitching::Document

A `Document` wraps a parsed GraphQL request, and handles the logistics of extracting its appropriate operation, variable definitions, and fragments. A `Document` should be built once for a request and passed through to other stitching components that utilize document information.

```ruby
query = "query FetchMovie($id: ID!) { movie(id:$id) { id genre } }"
document = GraphQL::Stitching::Document.new(query, operation_name: "FetchMovie")

document.ast # parsed AST via GraphQL.parse
document.string # normalized printed string
document.digest # SHA digest of the normalized string

document.variables # mapping of variable names to type definitions
document.fragments # mapping of fragment names to fragment definitions
```

### Preparing requests

Prior to planning and executing a request, the raw document and variables need to be prepared. This involves:

- Applying default values from variable definitions to request variables.
- Applying `@skip` and `@include` directives to the request document to conditionally format it.

These transformations are applied by calling `.prepare!` on the document. This should be done before planning or executing the request:

```ruby
document.prepare!
```
