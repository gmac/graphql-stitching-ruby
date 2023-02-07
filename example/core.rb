require 'rackup'
require 'json'
require 'byebug'
require 'graphql'
require 'graphql/stitching'

BRANDS = [
  { id: "gid://shopify/Brand/1", name: "Lego" },
  { id: "gid://shopify/Brand/2", name: "McTesting" },
]

PRODUCTS_REL_BRANDS = [
  ["gid://shopify/Product/6885875646486", "gid://shopify/Brand/1"],
  ["gid://shopify/Product/6561850556438", "gid://shopify/Brand/1"],
  ["gid://shopify/Product/6561850785814", "gid://shopify/Brand/1"],
  ["gid://shopify/Product/6561850884118", "gid://shopify/Brand/1"],
  ["gid://shopify/Product/7501637156886", "gid://shopify/Brand/2"],
]

class MyBrandsSchema < GraphQL::Schema
  class Boundary < GraphQL::Schema::Directive
    graphql_name "boundary"
    locations FIELD_DEFINITION
    argument :key, String
    repeatable true
  end

  class Brand < GraphQL::Schema::Object
    field :id, ID, null: false
    field :name, String, null: false
    field :products, ["MyBrandsSchema::Product"], null: false

    def products
      PRODUCTS_REL_BRANDS
        .select { |rel| rel[1] == object[:id] }
        .map { |rel| { id: rel[0] } }
    end
  end

  class Product < GraphQL::Schema::Object
    field :id, ID, null: false
    field :brands, [Brand], null: false

    def brands
      PRODUCTS_REL_BRANDS
        .select { |rel| rel[0] == object[:id] }
        .map { |rel| BRANDS.find { rel[1] == _1[:id] } }
    end
  end

  class Query < GraphQL::Schema::Object
    field :brands, [Brand, null: true], null: false do
      argument :ids, [ID], required: true
    end

    def brands(ids:)
      ids.map { |id| BRANDS.find { _1[:id] == id } }
    end

    field :brand_products, [Product, null: true], null: false do
      directive Boundary, key: "id"
      argument :ids, [ID], required: true
    end

    def brand_products(ids:)
      product_ids = PRODUCTS_REL_BRANDS.map { _1[0] }
      (product_ids & ids).map { |id| { id: id } }
    end
  end

  query Query
end

class StitchedApp
  def initialize
    file = File.open("#{__dir__}/env.json")
    headers = JSON.parse(file.read)
    file.close

    file = File.open("#{__dir__}/core.graphql")
    core_schema = GraphQL::Schema.from_definition(file.read)
    file.close

    file = File.open("#{__dir__}/graphiql.html")
    @graphiql = file.read
    file.close

    @supergraph = GraphQL::Stitching::Composer.new(schemas: {
      "core" => core_schema,
      "brands" => MyBrandsSchema,
    }).perform

    @supergraph.assign_location_url("core", "https://morebanana.myshopify.com/admin/api/2023-01/graphql.json", headers)
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

      plan = GraphQL::Stitching::Planner.new(
        supergraph: @supergraph,
        document: document,
      ).perform

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
