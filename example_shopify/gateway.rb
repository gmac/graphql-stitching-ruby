require 'rackup'
require 'json'
require 'graphql'
require 'graphql/stitching'
require_relative './local_schema'

class StitchedApp
  def initialize
    @graphiql = File.read("#{__dir__}/graphiql.html")

    supergraph_sdl = File.read("#{__dir__}/schemas/supergraph.graphql")
    supergraph_map = File.read("#{__dir__}/schemas/supergraph.json")
    headers = File.read("#{__dir__}/env.json")

    supergraph = GraphQL::Stitching::Supergraph.from_export(
      schema: supergraph_sdl,
      delegation_map: JSON.parse(supergraph_map),
      executables: {
        local: MyBrandsSchema,
        admin: GraphQL::Stitching::RemoteClient.new(
          url: "https://morebanana.myshopify.com/admin/api/2023-01/graphql.json",
          headers: JSON.parse(headers),
        )
      }
    )

    @gateway = GraphQL::Stitching::Gateway.new(supergraph: supergraph)
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
