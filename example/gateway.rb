require 'em_fiberscheduler'
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

    @supergraph = GraphQL::Stitching::Composer.new(schemas: {
      "products" => Schemas::Example::Products,
      "storefronts" => Schemas::Example::Storefronts,
      "manufacturers" => Schemas::Example::Manufacturers,
    }).perform

    @supergraph.assign_location_url("storefronts", "http://localhost:3001/graphql")
    @supergraph.assign_location_url("manufacturers", "http://localhost:3002/graphql")
  end

  def call(env)
    req = Rack::Request.new(env)
    case req.path_info
    when /graphql/
      # @todo extract composition + this workflow into some kind of "Gateway" convenience
      params = JSON.parse(req.body.read)
      document = GraphQL::Stitching::Document.new(params["query"], operation_name: params["operationName"])

      validation_errors = @supergraph.schema.validate(document.ast)
      if validation_errors.any?
        result = { errors: [validation_errors.map { |e| { message: e.message, path: e.path } }]}
        return [200, {"content-type" => "application/json"}, [JSON.generate(result)]]
      end

      # @todo
      # hoist variables... (nice to have)
      # generate document hash... (nice to have)
      # check for cached plan... (nice to have)

      plan = GraphQL::Stitching::Planner.new(
        supergraph: @supergraph,
        document: document,
      ).perform

      # cache generated plan... (nice to have)

      result = GraphQL::Stitching::Executor.new(
        supergraph: @supergraph,
        plan: plan.to_h,
        variables: params["variables"] || {},
      ).perform(document)

      [200, {"content-type" => "application/json"}, [JSON.generate(result)]]
    else
      [200, {"content-type" => "text/html"}, [@graphiql]]
    end
  end
end

Rackup::Handler.default.run(StitchedApp.new, :Port => 3000)
