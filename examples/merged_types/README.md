# Merged types example

This example demonstrates several stitched schemas running across small Rack servers with types merged across locations. The main "gateway" location stitches its local schema onto two remote endpoints.

Try running it:

```shell
cd examples/merged_types
bundle install
foreman start
```

Then visit the gateway service at [`http://localhost:3000`](http://localhost:3000) and try this query:

```graphql
query {
  storefront(id: "1") {
    id
    products {
      upc
      name
      price
      manufacturer {
        name
        address
        products { upc name }
      }
    }
  }
}
```

The above query collects data from all locations. You can also request introspections that resolve using the combined supergraph schema.
