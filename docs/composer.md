## GraphQL::Stitching::Composer

A `Composer` receives many individual `GraphQL:Schema` instances for various graph locations and _composes_ them into a combined [`Supergraph`](./supergraph.md) that is validated for integrity.

### Configuring composition

A `Composer` may be constructed with optional settings that tune how it builds a schema:

```ruby
composer = GraphQL::Stitching::Composer.new(
  query_name: "Query",
  mutation_name: "Mutation",
  description_merger: ->(values_by_location, info) { values_by_location.values.join("\n") },
  deprecation_merger: ->(values_by_location, info) { values_by_location.values.first },
  directive_kwarg_merger: ->(values_by_location, info) { values_by_location.values.last },
  root_field_location_selector: ->(locations, info) { locations.last },
)
```

Constructor arguments:

- **`query_name:`** _optional_, the name of the root query type in the composed schema; `Query` by default. The root query types from all location schemas will be merged into this type, regardless of their local names.

- **`mutation_name:`** _optional_, the name of the root mutation type in the composed schema; `Mutation` by default. The root mutation types from all location schemas will be merged into this type, regardless of their local names.

- **`description_merger:`** _optional_, a [value merger function](#value-merger-functions) for merging element description strings from across locations.

- **`deprecation_merger:`** _optional_, a [value merger function](#value-merger-functions) for merging element deprecation strings from across locations.

- **`directive_kwarg_merger:`** _optional_, a [value merger function](#value-merger-functions) for merging directive keyword arguments from across locations.

- **`root_field_location_selector:`** _optional_, selects a default routing location for root fields with multiple locations. Use this to prioritize sending root fields to their primary data sources (only applies while routing the root operation scope). This handler receives an array of possible locations and an info object with field information, and should return the prioritized location. The last location is used by default.

#### Value merger functions

Static data values such as element descriptions and directive arguments must also merge across locations. By default, the first non-null value encountered for a given element attribute is used. A value merger function may customize this process by selecting a different value or computing a new one:

```ruby
composer = GraphQL::Stitching::Composer.new(
  description_merger: ->(values_by_location, info) { values_by_location.values.compact.join("\n") },
)
```

A merger function receives `values_by_location` and `info` arguments; these provide possible values keyed by location and info about where in the schema these values were encountered:

```ruby
values_by_location = {
  "storefronts" => "A fabulous data type.",
  "products" => "An excellent data type.",
}

info = {
  type_name: "Product",
  # field_name: ...,
  # argument_name: ...,
  # directive_name: ...,
}
```

### Performing composition

Construct a `Composer` and call its `perform` method with location settings to compose a supergraph:

```ruby
storefronts_sdl = "type Query { ..."
products_sdl = "type Query { ..."

supergraph = GraphQL::Stitching::Composer.new.perform({
  storefronts: {
    schema: GraphQL::Schema.from_definition(storefronts_sdl),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001"),
    stitch: [{ field_name: "storefront", key: "id" }],
  },
  products: {
    schema: GraphQL::Schema.from_definition(products_sdl),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3002"),
  },
  my_local: {
    schema: MyLocalSchema,
  },
})

combined_schema = supergraph.schema
```

Location settings have top-level keys that specify arbitrary location names, each of which provide:

- **`schema:`** _required_, provides a `GraphQL::Schema` class for the location. This may be a class-based schema that inherits from `GraphQL::Schema`, or built from SDL (Schema Definition Language) string using `GraphQL::Schema.from_definition` and mapped to a remote location. The provided schema is only used for type reference and does not require any real data resolvers (unless it is also used as the location's executable, see below).

- **`executable:`** _optional_, provides an executable resource to be called when delegating a request to this location. Executables are `GraphQL::Schema` classes or any object with a `.call(location, source, variables, context)` method that returns a GraphQL response. Omitting the executable option will use the location's provided `schema` as the executable resource.

- **`stitch:`** _optional_, an array of configs used to dynamically apply `@stitch` directives to select root fields prior to composing. This is useful when you can't easily render stitching directives into a location's source schema.

### Merge patterns

The strategy used to merge source schemas into the combined schema is based on each element type:

- `Object` and `Interface` types merge their fields and directives together:
  - Common fields across locations must share a value type, and the weakest nullability is used.
  - Field and directive arguments merge using the same rules as `InputObject`.
  - Objects with unique fields across locations must implement [`@stitch` accessors](../README.md#merged-types).
  - Shared object types without `@stitch` accessors must contain identical fields.
  - Merged interfaces must remain compatible with all underlying implementations.

- `InputObject` types intersect arguments from across locations (arguments must appear in all locations):
  - Arguments must share a value type, and the strictest nullability across locations is used.
  - Composition fails if argument intersection would eliminate a non-null argument.

- `Enum` types merge their values based on how the enum is used:
  - Enums used anywhere as an argument will intersect their values (common values across all locations).
  - Enums used exclusively in read contexts will provide a union of values (all values across all locations).

- `Union` types merge all possible types from across all locations.

- `Scalar` types are added for all scalar names across all locations.

- `Directive` definitions are added for all distinct names across locations:
  - Arguments merge using the same rules as `InputObject`.
  - Stitching directives (both definitions and assignments) are omitted.

Note that the structure of a composed schema may change based on new schema additions and/or element usage (ie: changing input object arguments in one service may cause the intersection of arguments to change). Therefore, it's highly recommended that you use a [schema comparator](https://github.com/xuorig/graphql-schema_comparator) to flag regressions across composed schema versions.
