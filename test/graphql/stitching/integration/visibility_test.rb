# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/visibility"

describe 'GraphQL::Stitching, visibility' do
  def setup
    skip unless GraphQL::Stitching.supports_visibility?

    @supergraph = compose_definitions({
      "price" => Schemas::Visibility::PriceSchema,
      "inventory" => Schemas::Visibility::InventorySchema,
    }, {
      visibility_profiles: ["public", "private"],
    })

    @full_query = %|{
      sprocket(id: "1") {
        id
        price
        msrp
        quantityAvailable
        quantityInStock
      }
      sprockets(ids: ["1"]) {
        id
        price
        msrp
        quantityAvailable
        quantityInStock
      }
    }|

    @full_record = { 
      "id" => "1", 
      "price" => 20.99, 
      "msrp" => 10.99, 
      "quantityAvailable" => 23, 
      "quantityInStock" => 35,
    }
  end

  def test_fully_accessible_with_no_visibility_profile
    request = GraphQL::Stitching::Request.new(@supergraph, @full_query, context: {})
    assert request.validate.empty?

    expected = {
      "sprocket" => @full_record,
      "sprockets" => [@full_record],
    }

    assert_equal expected, request.execute.dig("data")
  end

  def test_no_private_or_hidden_fields_for_public_profile
    request = GraphQL::Stitching::Request.new(@supergraph, @full_query, context: {
      visibility_profile: "public",
    })

    expected = [
      { "code" => "undefinedField", "typeName" => "Sprocket", "fieldName" => "id" },
      { "code" => "undefinedField", "typeName" => "Sprocket", "fieldName" => "msrp" },
      { "code" => "undefinedField", "typeName" => "Sprocket", "fieldName" => "quantityInStock" },
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "sprockets" },
    ]

    assert_equal expected, request.validate.map(&:to_h).map { _1["extensions"] }
  end

  def test_no_hidden_fields_for_private_profile
    request = GraphQL::Stitching::Request.new(@supergraph, @full_query, context: {
      visibility_profile: "private",
    })
    
    expected = [
      { "code" => "undefinedField", "typeName" => "Sprocket", "fieldName" => "id" },
      { "code" => "undefinedField", "typeName" => "Sprocket", "fieldName" => "id" },
    ]

    assert_equal expected, request.validate.map(&:to_h).map { _1["extensions"] }
  end

  def test_accesses_stitched_data_in_public_profile
    query = %|{
      sprocket(id: "1") {
        price
        quantityAvailable
      }
    }|

    request = GraphQL::Stitching::Request.new(@supergraph, query, context: {
      visibility_profile: "public",
    })
    
    expected = {
      "sprocket" => { 
        "price" => 20.99,
        "quantityAvailable" => 23,
      },
    }

    assert_equal expected, request.execute.dig("data")
  end

  def test_accesses_stitched_data_in_private_profile
    query = %|{
      sprockets(ids: ["1"]) {
        price
        msrp
        quantityAvailable
        quantityInStock
      }
    }|

    request = GraphQL::Stitching::Request.new(@supergraph, query, context: {
      visibility_profile: "private",
    })
    
    expected = {
      "sprockets" => [{ 
        "price" => 20.99,
        "msrp" => 10.99, 
        "quantityAvailable" => 23, 
        "quantityInStock" => 35,
      }],
    }

    assert_equal expected, request.execute.dig("data")
  end
end
