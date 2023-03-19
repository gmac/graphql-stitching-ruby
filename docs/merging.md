## Merged types, advanced topics

### Errors

https://spec.graphql.org/June2018/#sec-Errors

### Null results

It's okay for a stitching query to return `null` for a merged type as long as all non-key fields of the type are nullable in the schema. For example, the following merge is valid:

```graphql
# -- Location A

type Movie {
  id: String!
  title: String!
}

type Query {
  movie(id: ID!): Movie @stitch(key: "id")
     # (id: "23") -> { id: "23", title: "Jurassic Park" }
}

# -- Location B

type Movie {
  id: String!
  rating: Int
}

type Query {
  movie(id: ID!): Movie @stitch(key: "id")
     # (id: "23") -> null
}
```

Merging an object from A and `null` from B is acceptible here because B is not obligated to provide any unique non-null fields:

```graphql
query {
  id
  title
  rating
}

# Merged result:
# {
#  id: "23",
#  title: "Jurassic Park",
#  rating: null
# }
```

### Multiple field locations

Fields of a merged type may exist in multiple locations. For example, here the `title` field shared across locations is okay because they have compatible field types:

```graphql
# -- Location A

type Movie {
  id: String!
  title: String!
  rating: Int!
}

# -- Location B

type Movie {
  id: String!
  title: String!
  reviews: [String!]!
}
```

Fields are always collected from the current routing location when possible. If we're already visiting location A and can get `title` there, we'll ignore the location B source. The reverse is true if we're starting from location B.

Fields that are not available in the current routing location are then resolved as follows:

1. Fields that are unique to one location automatically use their only source.
2. Any outstanding fields with multiple locations will select locations already in use.
3. Any outstanding fields will select the location that provides the highest quantity of outstanding fields.

### Root field locations
