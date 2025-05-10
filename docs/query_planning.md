## Query Planning


### Root selection routing

It's okay if root field names are repeated across locations. The entrypoint location will be used when routing root selections:

```graphql
# -- Location A

type Movie {
  id: String!
  rating: Int!
}

type Query {
  movie(id: ID!): Movie @stitch(key: "id") # << set as root entrypoint
}

# -- Location B

type Movie {
  id: String!
  reviews: [String!]!
}

type Query {
  movie(id: ID!): Movie @stitch(key: "id")
}

# -- Request

query {
  movie(id: "23") { id } # routes to Location A
}
```

Note that primary location routing _only_ applies to selections in the root scope. If the `Query` type appears again lower in the graph, then its fields are resolved as normal object fields outside of root context, for example:

```graphql
schema {
  query: Query # << root query, uses primary locations
}

type Query {
  subquery: Query # << subquery, acts as a normal object type
}
```

Also note that stitching queries (denoted by the `@stitch` directive) are completely separate from field routing concerns. A `@stitch` directive establishes a contract for resolving a given type in a given location. This contract is always used to collect stitching data, regardless of how request routing selected the location for use.

### Field selection routing

Fields of a merged type may exist in multiple locations. For example, the `title` field below is provided by both locations:

```graphql
# -- Location A

type Movie {
  id: String!
  title: String! # shared
  rating: Int!
}

type Query {
  movieA(id: ID!): Movie @stitch(key: "id")
}

# -- Location B

type Movie {
  id: String!
  title: String! # shared
  reviews: [String!]!
}

type Query {
  movieB(id: ID!): Movie @stitch(key: "id")
}
```

When planning a request, field selections always attempt to use the current routing location that originates from the selection root, for example:

```graphql
query GetTitleFromA {
  movieA(id: "23") { # <- enter via Location A
    title            # <- source from Location A
  }
}

query GetTitleFromB {
  movieB(id: "23") { # <- enter via Location B
    title            # <- source from Location B
  }
}
```

Field selections that are NOT available in the current routing location delegate to new locations as follows:

1. Fields with only one location automatically use that location.
2. Fields with multiple locations attempt to use a location added during step-1.
3. Any remaining fields pick a location based on their highest availability among locations.
