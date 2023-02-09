# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"

describe 'GraphQL::Stitching, multiple generations' do
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
            "_STITCH_upc" => "1",
            "_STITCH_typename" => "Product",
            "name" => "iPhone",
            "price"=>699.99,
            "manufacturer" => {
              "products"=>[
                { "upc" => "1", "name" => "iPhone" },
                { "upc" => "2", "name" => "Apple Watch" },
                { "upc" => "5", "name" => "iOS Survival Guide" },
              ],
              "_STITCH_id" => "1",
              "_STITCH_typename" => "Manufacturer",
              "name" => "Apple",
              "address" => "123 Main",
            },
          },
          {
            "upc" => "2",
            "_STITCH_upc" => "2",
            "_STITCH_typename" => "Product",
            "name" => "Apple Watch",
            "price"=>399.99,
            "manufacturer"=> {
              "products"=> [
                { "upc" => "1", "name" => "iPhone" },
                { "upc" => "2", "name" => "Apple Watch" },
                { "upc" => "5", "name" => "iOS Survival Guide" },
              ],
              "_STITCH_id" => "1",
              "_STITCH_typename" => "Manufacturer",
              "name" => "Apple",
              "address" => "123 Main",
            },
          },
        ],
      },
    }

    assert_equal expected, result.dig("data")
  end
end
