# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/interfaces"

describe 'GraphQL::Stitching, merged interfaces' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Interfaces::Products,
      "bundles" => Schemas::Interfaces::Bundles,
    })
  end

  def test_queries_merged_interface_via_concrete
    query = <<~GRAPHQL
      query($ids: [ID!]!) {
        bundles(ids: $ids) {
          id
          name
          price
          products {
            id
            name
            price
          }
        }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, query, { "ids" => ["1"] })

    expected_result = {
      "bundles" => [
        {
          "id" => "1",
          "name" => "Apple Gear",
          "price" => 999.99,
          "products" => [
            {
              "id" => "1",
              "name" => "iPhone",
              "price" => 699.99
            },
            {
              "id" => "2",
              "name" => "Apple Watch",
              "price" => 399.99
            },
          ],
        },
      ],
    }

    assert_equal expected_result, result["data"]
  end

  def test_queries_merged_interface_via_full_interface
    query = <<~GRAPHQL
      query($ids: [ID!]!) {
        result: productsBuyables(ids: $ids) {
          id
          name
          price
        }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, query, { "ids" => ["1"] })

    expected_result = {
      "result" => [
        {
          "id" => "1",
          "name" => "iPhone",
          "price" => 699.99,
        },
      ],
    }

    assert_equal expected_result, result["data"]
  end

  def test_queries_merged_interface_via_partial_interface
    query = <<~GRAPHQL
      query($ids: [ID!]!) {
        result: bundlesBuyables(ids: $ids) {
          id
          name
          price
          ... on Bundle {
            products {
              id
              name
              price
            }
          }
        }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, query, { "ids" => ["1"] })

    expected_result = {
      "result" => [
        {
          "id" => "1",
          "name" => "Apple Gear",
          "price" => 999.99,
          "products" => [
            {
              "id" => "1",
              "name" => "iPhone",
              "price" => 699.99
            },
            {
              "id" => "2",
              "name" => "Apple Watch",
              "price" => 399.99
            },
          ],
        },
      ],
    }

    assert_equal expected_result, result["data"]
  end

  def test_queries_merged_split_interface
    query = <<~GRAPHQL
      query($ids: [ID!]!) {
        result: productsSplit(ids: $ids) {
          id
          name
          price
        }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, query, { "ids" => ["1", "2"] })

    expected_result = {
      "result" => [
        {
          "id" => "1",
          "name" => "Widget",
          "price" => 10.99,
        },
        {
          "id" => "2",
          "name" => "Sprocket",
          "price" => 9.99,
        },
      ],
    }

    assert_equal expected_result, result["data"]
  end
end
