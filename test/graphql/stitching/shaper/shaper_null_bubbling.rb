# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"
require_relative "../../../schemas/conditionals"

describe "GraphQL::Stitching::Shaper, happy flow" do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Example::Products,
      "storefronts" => Schemas::Example::Storefronts,
      "manufacturers" => Schemas::Example::Manufacturers,
      "base" => Schemas::Conditionals::Abstracts,
      "exa" => Schemas::Conditionals::ExtensionsA,
      "exb" => Schemas::Conditionals::ExtensionsB,
    })
  end

  def xtest_basic_null_bubbling
    document = GraphQL::Stitching::Document.new("query {
      storefront(id: \"3\") {
        id
        products {
          upc
          manufacturer {
            name
            address
          }
        }
      }
    }
    ")

    raw_result = {
      "data"=>{
        "storefront"=>{
          "id"=>"3",
          "products"=>[
            {
              "upc"=>"6",
              "_STITCH_upc"=>"6",
              "_STITCH_typename"=>"Product",
              "manufacturer"=>{
                "_STITCH_id"=>"3",
                "_STITCH_typename"=>"Manufacturer",
                "name"=>"Narnia",
                "address"=>nil
              }
            }
          ]
        }
      }
    }

    expected_result = {
      "data"=>{
        "storefront"=>{
          "id"=>"3",
          "products"=>[
            {
              "upc"=>"6",
              "manufacturer"=>nil
            }
          ]
        }
      }
    }

    result = GraphQL::Stitching::Shaper.new(supergraph: @supergraph, document: document, raw: raw_result).perform!
    assert_equal expected_result, result
  end
end
