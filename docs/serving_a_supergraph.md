## Serving a supergraph

Serving a stitched schema should be optimized by environment. In `production` we favor speed and stability over flexibility, while in `development` we favor the reverse. Among the simplest ways to deploy a stitched schema is to compose it locally, write the composed schema as a `.graphql` file in your repo, and then load the pre-composed schema into a stitching client at runtime. This assures that composition always happens before deployment where failures can be detected.

### Exporting a production schema

1. Make a helper class for building your supergraph and exporting it as an SDL string:

```ruby
class SupergraphHelper
  def self.export
    client = GraphQL::Stitching::Client.new({
      remote: {
        schema: GraphQL::Schema.from_definition(File.read("db/schema/remote.graphql"))
      },
      local: {
        schema: MyLocalSchema
      }
    })

    client.supergraph.to_definition
  end
end
```

2. Setup a `rake` task for writing the export to a repo file:

```ruby
task :compose_supergraph do
  File.write("db/schema/supergraph.graphql", SupergraphHelper.export)
  puts "Schema composition was successful."
end

# bundle exec rake compose-supergraph
```

3. Also as part of the export Rake task, it's advisable to run a [schema comparator](https://github.com/xuorig/graphql-schema_comparator) across the `main` version and the current compilation to catch breaking change regressions that may arise [during composition](./composing_a_supergraph.md#schema-merge-patterns):

```ruby
task :compose_supergraph do
  # ...

  supergraph_file = "db/schema/supergraph.graphql"
  head_commit = %x(git merge-base HEAD origin/main).strip!
  head_source = %x(git show #{head_commit}:#{supergraph_file})

  old_schema = GraphQL::Schema.from_definition(head_source)
  new_schema = GraphQL::Schema.from_definition(File.read(supergraph_file))
  diff = GraphQL::SchemaComparator.compare(old_schema, new_schema)
  raise "Breaking changes found:\n-#{diff.breaking_changes.join("\n-")}" if diff.breaking?

  # ...
end
```

4. As a CI safeguard, be sure to write a test that compares the supergraph export against the current repo file. This assures the latest schema is always expored before deploying:

```ruby
test "supergraph export is up to date." do
  assert_equal SupergraphHelper.export, File.read("db/schema/supergraph.graphql")
end
```

### Supergraph controller

Then at runtime, execute requests using a client built for the environment. The `production` client should load the pre-composed export schema, while the `development` client can live reload using runtime composition. Be sure to memoize any static schemas that the development client uses to minimize reloading overhead:

```ruby
class SupergraphController < ApplicationController
  protect_from_forgery with: :null_session, prepend: true

  def execute
    # see visibility docs...
    visibility_profile = select_visibility_profile_for_audience(current_user)
    
    client.execute(
      query: params[:query],
      variables: params[:variables],
      operation_name: params[:operation_name],
      context: { visibility_profile: visibility_profile },
    )
  end

  private

  # select which client to use based on the environment...
  def client
    Rails.env.production? ? production_client : development_client
  end

  # production uses a pre-composed supergraph read from the repo...
  def production_client
    @production_client ||= begin
      supergraph_sdl = File.read("db/schema/supergraph.graphql")

      GraphQL::Stitching::Client.from_definition(supergraph_sdl, executables: {
        remote: GraphQL::Stitching::HttpExecutable.new("https://api.remote.com/graphql"),
        local: MyLocalSchema,
      }).tap do |client|
        # see performance and error handling docs...
        client.on_cache_read { ... }
        client.on_cache_write { ... }
        client.on_error { ... }
      end
    end
  end

  # development uses a supergraph composed on the fly...
  def development_client
    GraphQL::Stitching::Client.new(locations: {
      remote: {
        schema: remote_schema,
        executable: GraphQL::Stitching::HttpExecutable.new("https://localhost:3001/graphql"),
      },
      local: {
        schema: MyLocalSchema,
      },
    })
  end

  # other flat schemas used in development should be 
  # cached in memory to avoid as much runtime overhead as possible
  def remote_schema
    @remote_schema ||= GraphQL::Schema.from_definition(File.read("db/schema/remote.graphql"))
  end
end
```

### Client execution

The `Client.execute` method provides a mostly drop-in replacement for [`GraphQL::Schema.execute`](https://graphql-ruby.org/queries/executing_queries):

```ruby
client.execute(
  query: params[:query],
  variables: params[:variables],
  operation_name: params[:operation_name],
  context: { visibility_profile: visibility_profile },
)
```

It provides a subset of the standard `execute` arguments:

* `query`: a query (or mutation) as a string or parsed AST.
* `variables`: a hash of variables for the request.
* `operation_name`: the name of the operation to execute (when multiple are provided).
* `validate`: true if static validation should run on the supergraph schema before execution.
* `context`: an object passed through to executable calls and client hooks.

### Production reloading

It is possible to "hot" reload a production supergraph (ie: update the graph without a server deployment) using a background process to poll a remote supergraph file for changes and then build it into a new client for the controller at runtime. This works fine as long as locations and their executables don't change. If locations will change, the runtime _must_ be prepared to dynamically generate appropraite location executables.
