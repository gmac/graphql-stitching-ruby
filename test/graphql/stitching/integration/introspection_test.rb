# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"

describe 'GraphQL::Stitching, introspection' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Example::Products,
      "storefronts" => Schemas::Example::Storefronts,
      "manufacturers" => Schemas::Example::Manufacturers,
    })
  end

  def test_performs_full_introspection
    result = plan_and_execute(@supergraph, GraphQL::Introspection::INTROSPECTION_QUERY)

    introspection_types = result.dig("data", "__schema", "types").map { _1["name"] }
    expected_types = ["Manufacturer", "Product", "Query", "Storefront"]
    expected_types += ["Boolean", "Float", "ID", "Int", "String"]
    expected_types += @supergraph.memoized_introspection_types.keys
    assert_equal expected_types.sort, introspection_types.sort
  end

  def test_performs_schema_introspection_with_other_stitching
    result = plan_and_execute(@supergraph, %|
      {
        __schema {
          queryType { name }
        }
        product(upc: "1") {
          name
          manufacturer { name }
        }
      }
    |)

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

    assert_equal expected, result.to_h
  end

  def test_performs_type_introspection_with_other_stitching
    result = plan_and_execute(@supergraph, %|
      {
        __type(name: "Product") {
          name
          kind
        }
        product(upc: "1") {
          name
          manufacturer { name }
        }
      }
    |)

    expected = {
      "data" => {
        "__type" => {
          "name" => "Product",
          "kind" => "OBJECT",
        },
        "product" => {
          "name" => "iPhone",
          "manufacturer" => {
            "name" => "Apple",
          },
        },
      },
    }

    assert_equal expected, result.to_h
  end
end
