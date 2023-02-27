## Shopify Admin demo

This demonstration stitches a small local schema onto a subset of the Shopify Admin schema (only types used by `Product` are included in the stitched schema). This demonstrates a workflow where the combined schema is composed as a development build task, committed to the repository, and then loaded up directly at runtime.

### Setup

1. Make an `example_shopify/env.json` file (based on template) and add a valid access token for your shop.

2. Go into `example_shopify/local_schema.rb` and update product ids to reference random products in your shop.

3. `bundle install` and `npm install` (Node is used as a development build tool for schema filtering).

4. `bundle exec rake build` to rebuild and export the supergraph (combined schema).

5. `bundle exec ruby example_shopify/gateway.rb` to start the application, running on `http://localhost:3000`

The following query should load a local brand that stitches to Shopify Admin data, and back to local brand data:

```graphql
query {
  brands(ids: ["1"]) {
    name
    id
    products {
      id
      title
      brands {
        name
      }
    }
  }
}
```

### Make changes

You're welcome to make changes to the `example_shopify/local_schema.rb` file, which is just a small stand-alone GraphQL schema with dummy data resolvers. After making changes to the schema, you'll need to rebuild the supergraph and then restart your server:

1. `bundle exec rake build`

2. `bundle exec ruby example_shopify/gateway.rb`
