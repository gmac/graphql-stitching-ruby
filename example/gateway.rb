# frozen_string_literal: true

require 'rackup'
require 'json'
require 'byebug'
require 'graphql'
require 'graphql/stitching'
require_relative '../test/schemas/example'

class StitchedApp
  def initialize
    file = File.open("#{__dir__}/graphiql.html")
    @graphiql = file.read
    file.close

    @client = GraphQL::Stitching::Client.new(locations: {
      products: {
        schema: Schemas::Example::Products,
      },
      storefronts: {
        schema: Schemas::Example::Storefronts,
        executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3001/graphql"),
      },
      manufacturers: {
        schema: Schemas::Example::Manufacturers,
        executable: GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3002/graphql"),
      }
    })
  end

  def call(env)
    req = Rack::Request.new(env)
    case req.path_info
    when /graphql/
      params = JSON.parse(req.body.read)

      result = @client.execute(
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
