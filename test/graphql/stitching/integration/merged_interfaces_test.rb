# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/interfaces"

describe 'GraphQL::Stitching, merged interfaces' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Interfaces::Products,
      "bundles" => Schemas::Interfaces::Bundles,
    })

    @query = <<~GRAPHQL
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
  end

  def test_queries_merged_interfaces
    result = plan_and_execute(@supergraph, @query, { "ids" => ["1"] })

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
end
