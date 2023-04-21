## GraphQL::Stitching::Supergraph

A `Supergraph` is the singuar representation of a stitched graph. `Supergraph` is composed from many locations, and provides a combined GraphQL schema and delegation maps used to route incoming requests.

### Export and caching

A Supergraph is designed to be composed, cached, and restored. Calling the `export` method will return an SDL (Schema Definition Language) print of the combined graph schema and a delegation mapping hash. These can be persisted in any raw format that suits your stack:

```ruby
supergraph_sdl, delegation_map = supergraph.export

# stash these resources in Redis...
$redis.set("cached_supergraph_sdl", supergraph_sdl)
$redis.set("cached_delegation_map", JSON.generate(delegation_map))

# or, write the resources as files and commit them to your repo...
File.write("supergraph/schema.graphql", supergraph_sdl)
File.write("supergraph/delegation_map.json", JSON.generate(delegation_map))
```

To restore a Supergraph, call `from_export` proving the cached SDL string, the parsed JSON delegation mapping, and a hash of executables keyed by their location names:

```ruby
supergraph_sdl = $redis.get("cached_supergraph_sdl")
delegation_map = JSON.parse($redis.get("cached_delegation_map"))

supergraph = GraphQL::Stitching::Supergraph.from_export(
  schema: supergraph_sdl,
  delegation_map: delegation_map,
  executables: {
    my_remote: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3000"),
    my_local: MyLocalSchema,
  }
)
```
