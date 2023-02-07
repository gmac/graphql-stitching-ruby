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
      "data"=>{
        "storefront"=>{
          "id"=>"1",
          "products"=>[
            {
              "upc"=>"1",
              "_STITCH_upc"=>"1",
              "_STITCH_typename"=>"Product",
              "name"=>"iPhone",
              "price"=>699.99,
              "pages"=>1
            },
            {
              "upc"=>"2",
              "_STITCH_upc"=>"2",
              "_STITCH_typename"=>"Product",
              "name"=>"Apple Watch",
              "price"=>399.99
            }
          ]
        }
      }
    }

    expected_result = {
      "data"=>{
        "storefront"=>{
          "id"=>"1",
          "products"=>[
            {
              "upc"=>"1",
              "name"=>"iPhone",
              "price"=>699.99,
              "pages"=>1
            },
            {
              "upc"=>"2",
              "name"=>"Apple Watch",
              "price"=>399.99,
              "pages"=>nil
            }
          ]
        }
      }
    }

    result = GraphQL::Stitching::Shaper.new(supergraph: @supergraph, document: document, raw: raw_result).perform!
    assert_equal expected_result, result
  end

  def test_happy_flow_with_inline_fragments
    document = GraphQL::Stitching::Document.new("query($ids: [ID!]!) {
      fruits(ids: $ids) {
        ...on Apple { id extensions { color } }
        ...on Banana { id extensions { shape } }
      }
    }")

    raw_result = {
      "data"=>{
        "fruits"=>[
          {"id"=>"2", "extensions"=>{"_STITCH_id"=>"22", "_STITCH_typename"=>"BananaExtension", "shape"=>"crescent"}, "_STITCH_typename"=>"Banana"},
          {"id"=>"1", "extensions"=>{"_STITCH_id"=>"11", "_STITCH_typename"=>"AppleExtension", "color"=>"red"}, "_STITCH_typename"=>"Apple"},
        ]
      }
    }

    expected_result = {
      "data" => {
        "fruits" => [
          {"id"=>"2", "extensions"=>{"shape"=>"crescent"}},
          {"id"=>"1", "extensions"=>{"color"=>"red"}},
        ]
      }
    }

    result = GraphQL::Stitching::Shaper.new(supergraph: @supergraph, document: document, raw: raw_result).perform!
    assert_equal expected_result, result
  end

  def test_happy_flow_with_fragement_spreads
    document = GraphQL::Stitching::Document.new("query($ids: [ID!]!) {
      fruits(ids: $ids) {
        ...AppleAttrs
        ...BananaAttrs
      }
    }
    fragment AppleAttrs on Apple { id extensions { color } }
    fragment BananaAttrs on Banana { id extensions { shape } }")

    raw_result = {
      "data"=>{
        "fruits"=>[
          {"id"=>"2", "extensions"=>{"_STITCH_id"=>"22", "_STITCH_typename"=>"BananaExtension", "shape"=>"crescent"}, "_STITCH_typename"=>"Banana"},
          {"id"=>"1", "extensions"=>{"_STITCH_id"=>"11", "_STITCH_typename"=>"AppleExtension", "color"=>"red"}, "_STITCH_typename"=>"Apple"}
        ]
      }
    }

    expected_result = {
      "data"=>{
        "fruits"=>[
          {"id"=>"2", "extensions"=>{"shape"=>"crescent"}},
          {"id"=>"1", "extensions"=>{"color"=>"red"}}
        ]
      }
    }

    result = GraphQL::Stitching::Shaper.new(supergraph: @supergraph, document: document, raw: raw_result).perform!
    assert_equal expected_result, result
  end
end
