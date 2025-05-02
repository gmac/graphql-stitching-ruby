## Composing a Supergraph

A stitching client is constructed with many subgraph schemas, and must first _compose_ them into one unified schema that can introspect and validate supergraph requests. Composition only happens once upon initialization.

### Location settings

When building a client, pass a `locations` hash with named definitions for each subgraph location:

```ruby
client = GraphQL::Stitching::Client.new(locations: {
  products: {
    schema: GraphQL::Schema.from_definition(File.read("schemas/products.graphql")),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001"),
  },
  users: {
    schema: GraphQL::Schema.from_definition(File.read("schemas/users.graphql")),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3002"),
    stitch: [{ field_name: "users", key: "id" }],
  },
  my_local: {
    schema: MyLocalSchema,
  },
})
```

Location settings have top-level keys that specify arbitrary location name keywords, each of which provide:

- **`schema:`** _required_, provides a `GraphQL::Schema` class for the location. This may be a class-based schema that inherits from `GraphQL::Schema`, or built from SDL (Schema Definition Language) string using `GraphQL::Schema.from_definition` and mapped to a remote location. The provided schema is only used for type reference and does not require any real data resolvers (unless it's also used as the location's executable, see below).

- **`executable:`**, provides an executable resource to be called when delegating a request to this location, see [documentation](./executables.md). Omitting the executable option will use the location's provided `schema` as the executable resource.

- **`stitch:`**, an array of static configs used to dynamically apply [`@stitch` directives](./merged_types.md#merged-type-resolver-queries) to root fields while composing. Each config may specify `field_name`, `key`, `arguments`, and `type_name`.

### Composer options

When building a client, you may pass `composer_options` to tune how it builds a supergraph. All settings are optional:

```ruby
client = GraphQL::Stitching::Client.new(
  composer_options: {
    query_name: "Query",
    mutation_name: "Mutation",
    subscription_name: "Subscription",
    visibility_profiles: nil, # ["public", "private", ...]
    description_merger: ->(values_by_location, info) { values_by_location.values.join("\n") },
    deprecation_merger: ->(values_by_location, info) { values_by_location.values.first },
    default_value_merger: ->(values_by_location, info) { values_by_location.values.first },
    directive_kwarg_merger: ->(values_by_location, info) { values_by_location.values.last },
    root_entrypoints: {},
  },
  locations: {
    # ...
  }
)
```

- **`query_name:`**, the name of the root query type in the composed schema; `Query` by default. The root query types from all location schemas will be merged into this type, regardless of their local names.

- **`mutation_name:`**, the name of the root mutation type in the composed schema; `Mutation` by default. The root mutation types from all location schemas will be merged into this type, regardless of their local names.

- **`subscription_name:`**, the name of the root subscription type in the composed schema; `Subscription` by default. The root subscription types from all location schemas will be merged into this type, regardless of their local names.

- **`visibility_profiles:`**, an array of [visibility profiles](./visibility.md) that the supergraph responds to.

- **`description_merger:`**, a [value merger function](#value-merger-functions) for merging element description strings from across locations.

- **`deprecation_merger:`**, a [value merger function](#value-merger-functions) for merging element deprecation strings from across locations.

- **`default_value_merger:`**, a [value merger function](#value-merger-functions) for merging argument default values from across locations.

- **`directive_kwarg_merger:`**, a [value merger function](#value-merger-functions) for merging directive keyword arguments from across locations.

- **`root_entrypoints:`**, a hash of root field names mapped to their entrypoint locations, see [overlapping root fields](#overlapping-root-fields) below.

#### Value merger functions

Static data values such as element descriptions and directive arguments must also merge across locations. By default, the first non-null value encountered for a given element attribute is used. A value merger function may customize this process by selecting a different value or computing a new one:

```ruby
join_values_merger = ->(values_by_location, info) { values_by_location.values.compact.join("\n") }

client = GraphQL::Stitching::Client.new(
  composer_options: {
    description_merger: join_values_merger,
    deprecation_merger: join_values_merger,
    default_value_merger: join_values_merger,
    directive_kwarg_merger: join_values_merger,
  },
)
```

A merger function receives `values_by_location` and `info` arguments; these provide possible values keyed by location and info about where in the schema these values were encountered:

```ruby
values_by_location = {
  "users" => "A fabulous data type.",
  "products" => "An excellent data type.",
}

info = {
  type_name: "Product",
  # field_name: ...,
  # argument_name: ...,
  # directive_name: ...,
}
```

### Cached supergraphs

Composition is a nuanced process with a high potential for validation failures. While performing composition at runtime is fine in development mode, it becomes an unnecessary risk in production. It's much safer to compose your supergraph in development mode, cache the composition, and then rehydrate the supergraph from cache in production.

First, compose your supergraph in development mode and write it to file:

```ruby
client = GraphQL::Stitching::Client.new(locations: {
  products: {
    schema: GraphQL::Schema.from_definition(File.read("schemas/products.graphql")),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001"),
  },
  users: {
    schema: GraphQL::Schema.from_definition(File.read("schemas/users.graphql")),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3002"),
  },
  my_local: {
    schema: MyLocalSchema,
  },
})

File.write("schemas/supergraph.graphql", client.supergraph.to_definition)
```

Then in production, rehydrate the client using the cached supergraph and its production-appropriate executables:

```ruby
client = GraphQL::Stitching::Client.from_definition(
  File.read("schemas/supergraph.graphql"),
  executables: {
    products: GraphQL::Stitching::HttpExecutable.new(url: "https://products.myapp.com/graphql"),
    users: GraphQL::Stitching::HttpExecutable.new(url: "http://users.myapp.com/graphql"),
    my_local: MyLocalSchema,
  }
)
```

### Overlapping root fields

Some subgraph schemas may have overlapping root fields, such as the `product` field below. You may specify a `root_entrypoints` composer option to map overlapping root fields to a preferred location:

```ruby
infos_schema = %|
  type Product {
    id: ID!
    title: String!
  }
  type Query {
    product(id: ID!): Product @stitch(key: "id")
  }
|

prices_schema = %|
  type Product {
    id: ID!
    price: Float!
  }
  type Query {
    product(id: ID!): Product @stitch(key: "id")
  }
|

client = GraphQL::Stitching::Client.new(
  composer_options: {
    root_entrypoints: {
      "Query.product" => "infos",
    }
  },
  locations: {
    infos: {
      schema: GraphQL::Schema.from_definition(infos_schema),
      executable: #... ,
    },
    prices: {
      schema: GraphQL::Schema.from_definition(prices_schema),
      executable: #... ,
    },
  }
)
```

In the above, selecting the root `product` field will route to the "infos" schema by default. You should bias root fields to their most general-purpose location. This option _only_ applies to root fields where the planner has no starting location bias. Overlapping fields in lower-level positions will always bias towards the current planning location.

### Schema merge patterns

The strategy used to merge subgraph schemas into the combined supergraph schema is based on each element type:

- Arguments of fields, directives, and `InputObject` types intersect for each parent element across locations (an element's arguments must appear in all locations):
  - Arguments must share a value type, and the strictest nullability across locations is used.
  - Composition fails if argument intersection would eliminate a non-null argument.

- `Object` and `Interface` types merge their fields and directives together:
  - Common fields across locations must share a value type, and the weakest nullability is used.
  - Objects with unique fields across locations must implement [`@stitch` accessors](./merged_types.md).
  - Shared object types without `@stitch` accessors must contain identical fields.
  - Merged interfaces must remain compatible with all underlying implementations.

- `Enum` types merge their values based on how the enum is used:
  - Enums used anywhere as an argument will intersect their values (common values across all locations).
  - Enums used exclusively in read contexts will provide a union of values (all values across all locations).

- `Union` types merge all possible types from across all locations.

- `Scalar` types are added for all scalar names across all locations.

- `Directive` definitions are added for all distinct names across locations:
  - `@visibility` directives intersect their profiles, see [documentation](./visibility.md).
  - `@stitch` directives (both definitions and assignments) are omitted.
