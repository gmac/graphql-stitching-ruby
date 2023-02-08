# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/example"

describe "GraphQL::Stitching::Gateway" do
  def test_execute_valid_query

    schema_configs = {
      manufacturers: {
        schema: Schemas::Example::Manufacturers,
      },
      "storefronts" => {
        schema: Schemas::Example::Storefronts,
      },
      "products": {
        schema: Schemas::Example::Products,
      }
    }
    gateway = GraphQL::Stitching::Gateway.new(schema_configurations: schema_configs)

    query_string = 'query {
  storefront(id: "1") {
    id
    products {
      upc
      name
      price
      manufacturer {
        name
        address
        products { upc name }
      }
    }
  }
}'
    result = gateway.execute(query: query_string)
    expected_respone = { "data" => { "storefront" => { "id" => "1", "products" => [{ "upc" => "1", "_STITCH_upc" => "1", "_STITCH_typename" => "Product", "name" => "iPhone", "price" => 699.99, "manufacturer" => { "products" => [{ "upc" => "1", "name" => "iPhone" }, { "upc" => "2", "name" => "Apple Watch" }, { "upc" => "5", "name" => "iOS Survival Guide" }], "_STITCH_id" => "1", "_STITCH_typename" => "Manufacturer", "name" => "Apple", "address" => "123 Main" } }, { "upc" => "2", "_STITCH_upc" => "2", "_STITCH_typename" => "Product", "name" => "Apple Watch", "price" => 399.99, "manufacturer" => { "products" => [{ "upc" => "1", "name" => "iPhone" }, { "upc" => "2", "name" => "Apple Watch" }, { "upc" => "5", "name" => "iOS Survival Guide" }], "_STITCH_id" => "1", "_STITCH_typename" => "Manufacturer", "name" => "Apple", "address" => "123 Main" } }] } } }
    assert_equal expected_respone, result

    query_doc = GraphQL.parse(query_string)
    result = gateway.execute(query: query_doc)
    assert_equal expected_respone, result
  end

  def test_query_with_operation_name
    schema_configs = {
      "storefronts": {
        schema: Schemas::Example::Storefronts,
      }
    }
    gateway = GraphQL::Stitching::Gateway.new(schema_configurations: schema_configs)

    result = gateway.execute(query: 'query BestStoreFront { storefront(id: "1") { id } }  query SecondBest { storefront(id: "2") { id } }', operation_name: "SecondBest")
    expected_result = { "data" => { "storefront" => { "id" => "2" } } }
    assert_equal expected_result, result
  end

  def test_execute_with_remote_schema
    static_remote_data = { "data" => { "storefront" => { "id" => "10000" } } }
    schema_configs = {
      "storefronts": {
        schema: Schemas::Example::Storefronts,
        executable: Proc.new { static_remote_data }
      }
    }
    gateway = GraphQL::Stitching::Gateway.new(schema_configurations: schema_configs)
    result = gateway.execute(query: 'query { storefront(id: "1") { id } }')
    assert_equal static_remote_data, result
  end

  def test_query_with_variables
    schema_configs = {
      "storefronts": {
        schema: Schemas::Example::Storefronts,
      }
    }
    gateway = GraphQL::Stitching::Gateway.new(schema_configurations: schema_configs)

    result = gateway.execute(query: 'query BestStoreFront($storefrontID: ID!) { storefront(id: $storefrontID) { id } }', variables: { "storefrontID" => "1" })
    expected_result = { "data" => { "storefront" => { "id" => "1" } } }
    assert_equal expected_result, result
  end

  def test_invalid_query
    schema_configs = {
      "products": {
        schema: Schemas::Example::Products,
      }
    }
    gateway = GraphQL::Stitching::Gateway.new(schema_configurations: schema_configs)

    result = gateway.execute(query: 'query { invalid_selection }')
    error_response = { :errors => [[{ :message => "Field 'invalid_selection' doesn't exist on type 'Query'", :path => ["query", "invalid_selection"] }]] }
    assert_equal result, error_response
  end

  def test_skipping_validation_of_invalid_query
    schema_configs = {
      "products": {
        schema: Schemas::Example::Products,
      }
    }
    gateway = GraphQL::Stitching::Gateway.new(schema_configurations: schema_configs)

    assert_raises { gateway.execute(query: 'query { invalid_selection }', validate: false) }
  end
end
