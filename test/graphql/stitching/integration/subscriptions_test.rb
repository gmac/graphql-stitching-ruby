# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"
require_relative "../../../schemas/subscriptions"

describe 'GraphQL::Stitching, subscriptions' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Example::Products,
      "b" => Schemas::Example::Manufacturers,
      "c" => {
        schema: Schemas::Subscriptions::SubscriptionSchema,
        executable: -> (_req, _src, _vars) {
          { 
            "data" => { 
              "updateToProduct" => {
                "product" => { "_export_upc" => "1", "_export___typename" => "Product" }, 
                "manufacturer" => nil,
              },
            },
          }
        },
      },
    })

    @query = %|
      subscription {
        updateToProduct(upc: "1") {
          product { name }
          manufacturer { name }
        }
      }
    |

    @client = GraphQL::Stitching::Client.new(supergraph: @supergraph)
  end

  def test_subscription_stitches_subscribe_request
    result = @client.execute(@query)
    expected = {
      "data" => {
        "updateToProduct" => {
          "product" => { "name" => "iPhone" }, 
          "manufacturer" => nil,
        },
      },
    }

    assert_equal expected, result.to_h
  end

  def test_subscription_provides_update_handler
    result = @client.execute(@query)
    result.to_h.merge!({
      "data" => {
        "updateToProduct" => {
          "product" => { "_export_upc" => "1", "_export___typename" => "Product" }, 
          "manufacturer" => { "_export_id" => "1", "_export___typename" => "Manufacturer" },
        },
      },
    })

    expected = {
      "data" => {
        "updateToProduct" => {
          "product" => { "name" => "iPhone" }, 
          "manufacturer" => { "name" => "Apple" },
        },
      },
    }

    assert_equal expected, result.context[:stitch_subscription_update].call(result).to_h
  end
end
