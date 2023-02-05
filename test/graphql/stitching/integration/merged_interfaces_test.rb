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

  def test_queries_merged_interfaces
    query = "
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
    "

    result = plan_and_execute(@supergraph, query, { "ids" => ["1"] })
    pp result

    bundle = result.dig("data", "bundles", 0)
    expected_root = { "id" => "1", "name" => "Apple Gear", "price" => 999.99 }
    expected_products = [
      { "id" => "1", "name" => "iPhone", "price" => 699.99 },
      { "id" => "2", "name" => "Apple Watch", "price" => 399.99 },
    ]

    # @todo make this cleaner once there's a resolver
    assert_equal expected_root, bundle.slice("id", "name", "price")
    assert_equal expected_products, bundle["products"].map { _1.slice("id", "name", "price") }
  end
end
