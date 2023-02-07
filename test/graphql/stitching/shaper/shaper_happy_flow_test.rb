# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"

describe "GraphQL::Stitching::Shaper, happy flow" do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Example::Products,
      "storefronts" => Schemas::Example::Storefronts,
      "manufacturers" => Schemas::Example::Manufacturers,
    })
  end

  def test_simple_happy_flow
    document = GraphQL::Stitching::Document.new("query {
      storefront(id: \"1\") {
        id
        products {
          upc
          name
          price
          pages
        }
      }
    }
    ")
    raw_result = {
      "data": {
        "storefront": {
          "id": "1",
          "products": [
            {
              "upc": "1",
              "_STITCH_upc": "1",
              "_STITCH_typename": "Product",
              "name": "iPhone",
              "price": 699.99,
              "pages": 1
            },
            {
              "upc": "2",
              "_STITCH_upc": "2",
              "_STITCH_typename": "Product",
              "name": "Apple Watch",
              "price": 399.99
            }
          ]
        }
      }
    }

    expected_result = {
      :data=>{
        :storefront=>{
          :id=>"1",
          :products=>[
            {
              :upc=>"1",
              :name=>"iPhone",
              :price=>699.99,
              :pages=>1
            },
            {
              :upc=>"2",
              :name=>"Apple Watch",
              :price=>399.99,
              :pages=>nil
            }
          ]
        }
      }
    }

    result = GraphQL::Stitching::Shaper.new.perform(@supergraph.schema, document, raw_result)
    assert_equal expected_result, result
  end
end
