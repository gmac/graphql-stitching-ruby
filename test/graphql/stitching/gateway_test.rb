# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/example"

describe "GraphQL::Stitching::Gateway" do
  def setup_example_gateway
    @gateway = GraphQL::Stitching::Gateway.new(locations: {
      manufacturers: {
        schema: Schemas::Example::Manufacturers,
      },
      "storefronts" => {
        schema: Schemas::Example::Storefronts,
      },
      "products": {
        schema: Schemas::Example::Products,
      }
    })

    @query_string = <<~GRAPHQL
      query MyStore($id: ID!){
        storefront(id: $id) {
          id
          name
          products {
            upc
            name
            manufacturer {
              name
              products { upc name }
            }
          }
        }
      }
    GRAPHQL

    @expected_result = {
      "data" => {
        "storefront" => {
          "id" => "1",
          "name" => "eShoppe",
          "products" => [
            {
              "upc" => "1",
              "name" => "iPhone",
              "_STITCH_upc" => "1",
              "_STITCH_typename" => "Product",
              "manufacturer" => {
                "name" => "Apple",
                "products" => [
                  { "upc" => "1", "name" => "iPhone" },
                  { "upc" => "2", "name" => "Apple Watch" },
                  { "upc" => "5", "name" => "iOS Survival Guide" }
                ],
                "_STITCH_id" => "1",
                "_STITCH_typename" => "Manufacturer",
              }
            }, {
              "upc" => "2",
              "name" => "Apple Watch",
              "_STITCH_upc" => "2",
              "_STITCH_typename" => "Product",
              "manufacturer" => {
                "name" => "Apple",
                "products" => [
                  { "upc" => "1", "name" => "iPhone" },
                  { "upc" => "2", "name" => "Apple Watch" },
                  { "upc" => "5", "name" => "iOS Survival Guide" }
                ],
                "_STITCH_id" => "1",
                "_STITCH_typename" => "Manufacturer",
              }
            }
          ]
        }
      }
    }
  end

  def test_execute_valid_query_via_string
    setup_example_gateway

    result = @gateway.execute(
      query: @query_string,
      variables: { "id" => "1" },
      operation_name: "MyStore",
    )

    assert_equal @expected_result, result
  end

  def test_execute_valid_query_via_ast
    setup_example_gateway

    result = @gateway.execute(
      query: GraphQL.parse(@query_string),
      variables: { "id" => "1" },
      operation_name: "MyStore",
    )

    assert_equal @expected_result, result
  end

  def test_gateway_builds_with_provided_supergraph
    export_schema = "type Thing { id: String } type Query { thing: Thing }"
    export_mapping = { "fields" => {}, "boundaries" => {} }
    supergraph = GraphQL::Stitching::Supergraph.from_export(export_schema, export_mapping)
    assert GraphQL::Stitching::Gateway.new(supergraph: supergraph)
  end

  def test_errors_for_invalid_supergraph
    assert_error "must be a GraphQL::Stitching::Supergraph" do
      GraphQL::Stitching::Gateway.new(supergraph: {})
    end
  end

  def test_errors_for_both_locations_and_supergraph
    assert_error "Cannot provide both locations and a supergraph" do
      GraphQL::Stitching::Gateway.new(locations: {}, supergraph: {})
    end
  end

  def test_query_with_operation_name
    setup_example_gateway

    queries = <<~GRAPHQL
      query BestStorefront {
        storefront(id: "1") { id }
      }
      query SecondBest {
        storefront(id: "2") { id }
      }
    GRAPHQL

    result = @gateway.execute(query: queries, operation_name: "SecondBest")

    expected_result = { "data" => { "storefront" => { "id" => "2" } } }
    assert_equal expected_result, result
  end

  def test_location_with_executable
    static_remote_data = { "data" => { "storefront" => { "id" => "10000" } } }

    gateway = GraphQL::Stitching::Gateway.new(locations: {
      storefronts: {
        schema: Schemas::Example::Storefronts,
        executable: Proc.new { static_remote_data }
      }
    })

    result = gateway.execute(query: "query { storefront(id: \"1\") { id } }")
    assert_equal static_remote_data, result
  end

  def test_query_with_variables
    gateway = GraphQL::Stitching::Gateway.new(locations: {
      storefronts: {
        schema: Schemas::Example::Storefronts,
      }
    })

    query = <<~GRAPHQL
      query BestStoreFront($storefrontID: ID!) {
        storefront(id: $storefrontID) { id }
      }
    GRAPHQL

    result = gateway.execute(query: query, variables: { "storefrontID" => "1" })

    expected_result = { "data" => { "storefront" => { "id" => "1" } } }
    assert_equal expected_result, result
  end

  def test_caching_hooks_store_query_plans
    setup_example_gateway
    cache = {}

    test_query = <<~GRAPHQL
      query {
        product(upc: "1") { price }
      }
    GRAPHQL

    @gateway.on_cache_read { |key| cache[key] }
    @gateway.on_cache_write { |key, payload| cache[key] = payload.gsub("price", "name") }

    uncached_result = @gateway.execute(query: test_query)
    expected_uncached = { "data" => { "product" => { "price" => 699.99 } } }
    assert_equal expected_uncached, uncached_result

    cached_result = @gateway.execute(query: test_query)
    expected_cached = { "data" => { "product" => { "name" => "iPhone" } } }
    assert_equal expected_cached, cached_result
  end

  def test_caching_hooks_receive_request_context
    gateway = GraphQL::Stitching::Gateway.new(locations: {
      products: {
        schema: Schemas::Example::Products,
      }
    })

    context = { key: "R2d2c3P0" }
    read_context = nil
    write_context = nil

    gateway.on_cache_read do |key, context|
      read_context = context[:key]
      nil
    end
    gateway.on_cache_write do |key, payload, context|
      write_context = context[:key]
      nil
    end

    gateway.execute(query: "{ product(upc: \"1\") { price } }", context: context)
    assert_equal context[:key], read_context
    assert_equal context[:key], write_context
  end

  def test_invalid_query
    gateway = GraphQL::Stitching::Gateway.new(locations: {
      products: {
        schema: Schemas::Example::Products,
      }
    })

    result = gateway.execute(query: "query { invalidSelection }")
    expected_errors = [{
      "message" => "Field 'invalidSelection' doesn't exist on type 'Query'",
      "path" => ["query", "invalidSelection"],
    }]

    assert_nil result["data"]
    assert_equal expected_errors, result["errors"].map { _1.slice("message", "path") }
  end

  def test_errors_are_handled_by_default
    gateway = GraphQL::Stitching::Gateway.new(locations: {
      products: {
        schema: Schemas::Example::Products,
      }
    })

    result = gateway.execute(query: 'query { invalidSelection }', validate: false)

    expected_errors = [{
      "message" => "An unexpected error occured.",
      "path" => [],
    }]

    assert_nil result["data"]
    assert_equal expected_errors, result["errors"]
  end

  def test_errors_trigger_hooks_that_may_return_a_custom_message
    gateway = GraphQL::Stitching::Gateway.new(locations: {
      products: {
        schema: Schemas::Example::Products,
      }
    })

    gateway.on_error do |_err, context|
      "An error occured. Request id: #{context[:request_id]}"
    end

    result = gateway.execute(
      query: 'query { invalidSelection }',
      context: { request_id: "R2d2c3P0" },
      validate: false
    )

    expected_errors = [{
      "message" => "An error occured. Request id: R2d2c3P0",
      "path" => [],
    }]

    assert_nil result["data"]
    assert_equal expected_errors, result["errors"]
  end
end
