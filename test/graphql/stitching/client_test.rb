# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/example"

describe "GraphQL::Stitching::Client" do
  def setup_client
    @client = GraphQL::Stitching::Client.new(locations: {
      manufacturers: {
        schema: Schemas::Example::Manufacturers,
      },
      storefronts: {
        schema: Schemas::Example::Storefronts,
      },
      products: {
        schema: Schemas::Example::Products,
      }
    })

    @query_string = %|
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
    |

    @expected_result = {
      "data" => {
        "storefront" => {
          "id" => "1",
          "name" => "eShoppe",
          "products" => [
            {
              "upc" => "1",
              "name" => "iPhone",
              "manufacturer" => {
                "name" => "Apple",
                "products" => [
                  { "upc" => "1", "name" => "iPhone" },
                  { "upc" => "2", "name" => "Apple Watch" },
                  { "upc" => "5", "name" => "iOS Survival Guide" }
                ],
              }
            }, {
              "upc" => "2",
              "name" => "Apple Watch",
              "manufacturer" => {
                "name" => "Apple",
                "products" => [
                  { "upc" => "1", "name" => "iPhone" },
                  { "upc" => "2", "name" => "Apple Watch" },
                  { "upc" => "5", "name" => "iOS Survival Guide" }
                ],
              }
            }
          ]
        }
      }
    }
  end

  def test_execute_valid_query_via_string
    setup_client

    result = @client.execute(
      query: @query_string,
      variables: { "id" => "1" },
      operation_name: "MyStore",
    )

    assert_equal @expected_result, result
  end

  def test_execute_valid_query_via_ast
    setup_client

    result = @client.execute(
      query: GraphQL.parse(@query_string),
      variables: { "id" => "1" },
      operation_name: "MyStore",
    )

    assert_equal @expected_result, result
  end

  def test_prepares_requests_before_handling
    setup_client

    @query_string = %|
      query MyStore($id: ID!, $products: Int = 2) {
        storefront(id: $id) {
          id
          name
          products(first: $products) @skip(if: true) {
            upc
            name
          }
        }
      }
    |

    result = @client.execute(
      query: GraphQL.parse(@query_string),
      variables: { "id" => "1" },
      operation_name: "MyStore",
    )

    @expected_result = {
      "data" => {
        "storefront" => {
          "id" => "1",
          "name" => "eShoppe",
        }
      }
    }

    assert_equal @expected_result, result
  end

  def test_client_builds_with_provided_supergraph
    supergraph = supergraph_from_schema(
      "type Thing { id: String } type Query { thing: Thing }",
      executables: {
        alpha: Proc.new { true },
      }
    )
    assert GraphQL::Stitching::Client.new(supergraph: supergraph)
  end

  def test_errors_for_invalid_supergraph
    assert_error "must be a GraphQL::Stitching::Supergraph" do
      GraphQL::Stitching::Client.new(supergraph: {})
    end
  end

  def test_errors_for_both_locations_and_supergraph
    assert_error "Cannot provide both locations and a supergraph" do
      GraphQL::Stitching::Client.new(locations: {}, supergraph: {})
    end
  end

  def test_query_with_operation_name
    setup_client

    queries = %|
      query BestStorefront {
        storefront(id: "1") { id }
      }
      query SecondBest {
        storefront(id: "2") { id }
      }
    |

    result = @client.execute(query: queries, operation_name: "SecondBest")

    expected_result = { "data" => { "storefront" => { "id" => "2" } } }
    assert_equal expected_result, result
  end

  def test_returns_error_for_required_operation_name
    setup_client

    queries = %|
      query BestStorefront {
        storefront(id: "1") { id }
      }
      query SecondBest {
        storefront(id: "2") { id }
      }
    |

    result = @client.execute(query: queries)

    expected_errors = [
      { "message" => "An operation name is required when sending multiple operations." },
    ]
    assert_equal expected_errors, result["errors"]
  end

  def test_returns_error_for_operation_name_not_found
    setup_client

    queries = %|
      query { storefront(id: "1") { id } }
    |

    result = @client.execute(query: queries, operation_name: "Sfoo")

    expected_errors = [
      { "message" => "Invalid root operation for given name and operation type." },
    ]
    assert_equal expected_errors, result["errors"]
  end

  def test_returns_graphql_error_for_parser_failures
    setup_client

    queries = %|
      query BestStorefront { sfoo }}
    |

    result = @client.execute(query: queries)
    expected_locs = [{ "line" => 2, "column" => 36 }]

    assert_equal 1, result["errors"].length
    assert result["errors"][0]["message"].include?("RCURLY")
    assert_equal expected_locs, result["errors"][0]["locations"]
  end

  def test_location_with_executable
    static_remote_data = { "data" => { "storefront" => { "id" => "10000" } } }

    client = GraphQL::Stitching::Client.new(locations: {
      storefronts: {
        schema: Schemas::Example::Storefronts,
        executable: Proc.new { static_remote_data }
      }
    })

    result = client.execute(query: "query { storefront(id: \"1\") { id } }")
    assert_equal static_remote_data, result
  end

  def test_query_with_variables
    client = GraphQL::Stitching::Client.new(locations: {
      storefronts: {
        schema: Schemas::Example::Storefronts,
      }
    })

    query = %|
      query BestStoreFront($storefrontID: ID!) {
        storefront(id: $storefrontID) { id }
      }
    |

    result = client.execute(query: query, variables: { "storefrontID" => "1" })

    expected_result = { "data" => { "storefront" => { "id" => "1" } } }
    assert_equal expected_result, result
  end

  def test_caching_hooks_store_query_plans
    setup_client
    cache = {}

    test_query = %|
      query {
        product(upc: "1") { price }
      }
    |

    @client.on_cache_read { |req| cache[req.digest] }
    @client.on_cache_write { |req, payload| cache[req.digest] = payload.gsub("price", "name price") }

    uncached_result = @client.execute(query: test_query)
    expected_uncached = { "data" => { "product" => { "price" => 699.99 } } }
    assert_equal expected_uncached, uncached_result

    cached_result = @client.execute(query: test_query)
    expected_cached = { "data" => { "product" => { "name" => "iPhone", "price" => 699.99 } } }
    assert_equal expected_cached, cached_result
  end

  def test_caching_hooks_receive_request_context
    client = GraphQL::Stitching::Client.new(locations: {
      products: {
        schema: Schemas::Example::Products,
      }
    })

    context = { key: "R2d2c3P0" }
    read_context = nil
    write_context = nil

    client.on_cache_read do |req|
      read_context = req.context[:key]
      nil
    end
    client.on_cache_write do |req, payload|
      write_context = req.context[:key]
      nil
    end

    client.execute(query: %|{ product(upc: "1") { price } }|, context: context)
    assert_equal context[:key], read_context
    assert_equal context[:key], write_context
  end

  def test_invalid_query
    client = GraphQL::Stitching::Client.new(locations: {
      products: {
        schema: Schemas::Example::Products,
      }
    })

    result = client.execute(query: "query { invalidSelection }")
    expected_errors = [{
      "message" => "Field 'invalidSelection' doesn't exist on type 'Query'",
      "path" => ["query", "invalidSelection"],
    }]

    assert_nil result["data"]
    assert_equal expected_errors, result["errors"].map { _1.slice("message", "path") }
  end

  def test_errors_are_handled_by_default
    client = GraphQL::Stitching::Client.new(locations: {
      products: {
        schema: Schemas::Example::Products,
      }
    })

    result = client.execute(query: 'query { invalidSelection }', validate: false)

    expected_errors = [{
      "message" => "An unexpected error occured.",
    }]

    assert_nil result["data"]
    assert_equal expected_errors, result["errors"]
  end

  def test_errors_trigger_hooks_that_may_return_a_custom_message
    client = GraphQL::Stitching::Client.new(locations: {
      products: {
        schema: Schemas::Example::Products,
      }
    })

    client.on_error do |req, _err|
      "An error occured. Request id: #{req.context[:request_id]}"
    end

    result = client.execute(
      query: 'query { invalidSelection }',
      context: { request_id: "R2d2c3P0" },
      validate: false
    )

    expected_errors = [{
      "message" => "An error occured. Request id: R2d2c3P0",
    }]

    assert_nil result["data"]
    assert_equal expected_errors, result["errors"]
  end
end
