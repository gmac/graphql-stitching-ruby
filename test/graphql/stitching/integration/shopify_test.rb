# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/shopify/products"
require_relative "../../../schemas/shopify/collections"
require_relative "../../../schemas/shopify/variants"

describe 'GraphQL::Stitching, shopify services' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Shopify::ProductsScope,
      "collections" => Schemas::Shopify::CollectionsScope,
      "variants" => Schemas::Shopify::VariantsScope,
    })
  end

  def test_select_a_bunch_of_data
    query = %|
      query($ids: [ID!]!) {
        products(ids: $ids) {
          id
          title
          variants {
            id
            title
            product {
              id
              title
            }
          }
          collections {
            id
            title
            products {
              id
              title
            }
          }
        }
      }
    |

    ids = ["Product/1", "Product/2", "Product/4", "Product/5", "Product/6"]

    result = plan_and_execute(@supergraph, query, { "ids" => ids }) do |plan|
      plan = plan.as_json
      plan[:ops].each do |op|
        op[:resolver] = @supergraph.resolvers_by_version[op[:resolver]]&.as_json
      end
      pp plan
    end

    pp result.to_h
  end
end
