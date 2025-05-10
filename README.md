## GraphQL Stitching for Ruby

GraphQL stitching composes a single schema from multiple underlying GraphQL resources, then smartly proxies portions of incoming requests to their respective locations in dependency order and returns the merged results. This allows an entire graph of locations to be queried through one combined GraphQL surface area.

![Stitched graph](./docs/images/stitching.png)

**Supports:**
- All operation types: query, mutation, and [subscription](./docs/subscriptions.md).
- Merged object and abstract types joining though multiple keys.
- Shared objects, fields, enums, and inputs across locations.
- Combining local and remote schemas.
- [Visibility controls](./docs/visibility.md) for hiding schema elements.
- [File uploads](./docs/executables.md) via multipart forms.
- Tested with all minor versions of `graphql-ruby`.

**NOT Supported:**
- Computed fields (ie: federation-style `@requires`).
- Defer/stream.

This Ruby implementation is designed as a generic library to join basic spec-compliant GraphQL schemas using their existing types and fields in a do-it-yourself capacity. The opportunity here is for a Ruby application to stitch its local schemas together or onto remote sources without requiring an additional proxy service running in another language. If your goal is a purely high-throughput federation gateway with managed schema deployments, consider more opinionated frameworks such as [Apollo Federation](https://www.apollographql.com/docs/federation/).

## Documentation

1. [Introduction](./docs/introduction.md)
1. [Composing a supergraph](./docs/composing_a_supergraph.md)
1. [Merged types](./docs/merged_types.md)
1. [Executables & file uploads](./docs/executables.md)
1. [Serving a supergraph](./docs/serving_a_supergraph.md)
1. [Visibility controls](./docs/visibility.md)
1. [Performance concerns](./docs/performance.md)
1. [Error handling](./docs/error_handling.md)
1. [Subscriptions](./docs/subscriptions.md)

## Quick Start

Add to your Gemfile:

```ruby
gem "graphql-stitching"
```

Run `bundle install`, then require unless running an autoloading framework (Rails, etc):

```ruby
require "graphql/stitching"
```

A stitched schema is [_composed_](./docs/composing_a_supergraph.md) from many _subgraph_ schemas. These can be remote APIs expressed as Schema Definition Language (SDL), or local schemas built from Ruby classes. Subgraph type names that overlap become [_merged types_](./docs/merged_types.md), and require `@stitch` directives to identify where each variant of the type can be fetched and what key field links them:

_schemas/product_infos.graphql_
```graphql
directive @stitch(key: String!, arguments: String) repeatable on FIELD_DEFINITION

type Product {
  id: ID!
  name: String!
}

type Query {
  product(id: ID!): Product @stitch(key: "id")
}
```

_product_prices_schema.rb_
```ruby
class Product < GraphQL::Schema::Object
  field :id, ID, null: false
  field :price, Float, null: false
end

class Query < GraphQL::Schema::Object
  field :products, [Product, null: true], null: false do |f|
    f.directive(GraphQL::Stitching::Directives::Stitch, key: "id")
    f.argument(ids: [ID, null: false], required: true)
  end

  def products(ids:)
    products_by_id = ProductModel.where(id: ids).index_by(&:id)
    ids.map { |id| products_by_id[id] }
  end
end

class ProductPricesSchema < GraphQL::Schema
  directive(GraphQL::Stitching::Directives::Stitch)
  query(Query)
end
```

These subgraph schemas are composed into a _supergraph_, or, a single combined schema that can be queried as one. Remote schemas are mapped to their resolver locations using [_executables_](./docs/executables.md):

```ruby
client = GraphQL::Stitching::Client.new(locations: {
  infos: {
    schema: GraphQL::Schema.from_definition(File.read("schemas/product_infos.graphql")),
    executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001"),
  },
  prices: {
    schema: ProductPricesSchema,
  },
})
```

A stitching client then acts as a drop-in replacement for [serving GraphQL queries](./docs/serving_a_supergraph.md) using the combined schema. Internally, a query is broken down by location and sequenced into multiple requests, then all results are merged and shaped to match the original query.

```ruby
query = %|
  query FetchProduct($id: ID!) {
    product(id: $id) {
      name  # from infos schema
      price # from prices schema
    }
  }
|

result = client.execute(
  query: query,
  variables: { "id" => "1" },
  operation_name: "FetchProduct",
)
```

## Examples

Clone this repo, then `cd` into each example and follow its README instructions.

- [Merged types](./examples/merged_types)
- [File uploads](./examples/file_uploads)
- [Subscriptions](./examples/subscriptions)

## Tests

```shell
bundle install
bundle exec rake test [TEST=path/to/test.rb]
```
