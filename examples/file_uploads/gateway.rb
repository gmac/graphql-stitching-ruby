# frozen_string_literal: true

require 'rackup'
require 'json'
require 'graphql'
require_relative '../../lib/graphql/stitching'
require_relative './helpers'

class StitchedApp
  def initialize
    @client = GraphQL::Stitching::Client.new(locations: {
      gateway: {
        schema: GatewaySchema,
      },
      remote: {
        schema: RemoteSchema,
        executable: GraphQL::Stitching::HttpExecutable.new(
          url: "http://localhost:3001",
          upload_types: ["Upload"]
        ),
      },
    })
  end

  def call(env)
    params = apollo_upload_server_middleware_params(env)
    result = @client.execute(
      query: params["query"],
      variables: params["variables"],
      operation_name: params["operationName"],
    )

    [200, {"content-type" => "application/json"}, [JSON.generate(result)]]
  end
end

Rackup::Handler.default.run(StitchedApp.new, :Port => 3000)
