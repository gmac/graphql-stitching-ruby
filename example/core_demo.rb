require 'rackup'
require 'json'
require 'graphql'
require 'graphql/stitching'
require_relative './core_demo_schema'

class StitchedApp
  def initialize
    file = File.open("#{__dir__}/env.json")
    headers = JSON.parse(file.read)
    file.close

    file = File.open("#{__dir__}/graphiql.html")
    @graphiql = file.read
    file.close

    file = File.open("#{__dir__}/core.graphql")
    core_schema_sdl = file.read
    file.close

    @gateway = GraphQL::Stitching::Gateway.new(locations: {
      core: {
        schema: GraphQL::Stitching.schema_from_definition(
          core_schema_sdl,
          stitch_directives: [{ type_name: "QueryRoot", field_name: "nodes", key: "id" }],
        ),
        executable: GraphQL::Stitching::RemoteClient.new(
          url: "https://morebanana.myshopify.com/admin/api/2023-01/graphql.json",
          headers: headers,
        ),
      },
      brands: {
        schema: MyBrandsSchema,
      },
    })
  end

  def call(env)
    req = Rack::Request.new(env)
    case req.path_info
    when /graphql/
      params = JSON.parse(req.body.read)

      result = @gateway.execute(
        query: params["query"],
        variables: params["variables"],
        operation_name: params["operationName"],
      )

      [200, {"content-type" => "application/json"}, [JSON.generate(result)]]
    else
      [200, {"content-type" => "text/html"}, [@graphiql]]
    end
  end
end

Rackup::Handler.default.run(StitchedApp.new, :Port => 3000)
