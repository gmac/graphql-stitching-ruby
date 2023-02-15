# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"

describe 'GraphQL::Stitching, example' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Example::Products,
      "storefronts" => Schemas::Example::Storefronts,
      "manufacturers" => Schemas::Example::Manufacturers,
    })

    @query = <<~GRAPHQL
      query($id: ID!) {
        storefront(id: $id) {
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
      }
    GRAPHQL
  end

  def test_resolves_multiple_generations
    result = plan_and_execute(@supergraph, @query, { "id" => "1" })
    expected = {
      "storefront" => {
        "id" => "1",
        "products" => [
          {
            "upc" => "1",
            "name" => "iPhone",
            "price"=>699.99,
            "manufacturer" => {
              "products"=>[
                { "upc" => "1", "name" => "iPhone" },
                { "upc" => "2", "name" => "Apple Watch" },
                { "upc" => "5", "name" => "iOS Survival Guide" },
              ],
              "name" => "Apple",
              "address" => "123 Main",
            },
          },
          {
            "upc" => "2",
            "name" => "Apple Watch",
            "price"=>399.99,
            "manufacturer"=> {
              "products"=> [
                { "upc" => "1", "name" => "iPhone" },
                { "upc" => "2", "name" => "Apple Watch" },
                { "upc" => "5", "name" => "iOS Survival Guide" },
              ],
              "name" => "Apple",
              "address" => "123 Main",
            },
          },
        ],
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_provides_raw_result_by_request
     @query = <<~GRAPHQL
      query($id: ID!) {
        storefront(id: $id) {
          products {
            upc
            name
            price
          }
        }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, @query, { "id" => "1" }, raw: true)
    expected = {
      "storefront" => {
        "products" => [
          {
            "upc" => "1",
            "_STITCH_upc" => "1",
            "_STITCH_typename" => "Product",
            "name" => "iPhone",
            "price"=>699.99,
          },
          {
            "upc" => "2",
            "_STITCH_upc" => "2",
            "_STITCH_typename" => "Product",
            "name" => "Apple Watch",
            "price"=>399.99,
          },
        ],
      },
    }

    assert_equal expected, result.dig("data")
  end
end
