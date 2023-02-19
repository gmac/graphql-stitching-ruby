# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"
require_relative "../../../schemas/introspection"

describe 'GraphQL::Stitching, introspection' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Example::Products,
      "storefronts" => Schemas::Example::Storefronts,
      "manufacturers" => Schemas::Example::Manufacturers,
    })
  end

  def test_performs_full_introspection
    result = plan_and_execute(@supergraph, INTROSPECTION_QUERY)

    introspection_types = result.dig("data", "__schema", "types").map { _1["name"] }
    expected_types = ["Manufacturer", "Product", "Query", "Storefront"]
    expected_types += ["Boolean", "Float", "ID", "Int", "String"]
    expected_types += GraphQL::Stitching::Supergraph::INTROSPECTION_TYPES
    assert_equal expected_types.sort, introspection_types.sort
  end

  def test_performs_partial_introspection_with_other_stitching
    query = <<~GRAPHQL
      {
        __schema {
          queryType { name }
        }
        product(upc: "1") {
          name
          manufacturer { name }
        }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, query)

    expected = {
      "data" => {
        "__schema" => {
          "queryType" => {
            "name" => "Query",
          },
        },
        "product" => {
          "name" => "iPhone",
          "manufacturer" => {
            "name" => "Apple",
          },
        },
      },
    }

    assert_equal expected, result
  end
end
