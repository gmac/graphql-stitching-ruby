# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/shopify"

describe 'GraphQL::Stitching, shopify services' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Shopify::ProductsService,
      "collections" => Schemas::Shopify::CollectionsService,
      "variants" => Schemas::Shopify::VariantsService,
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

    result = plan_and_execute(@supergraph, query, { "ids" => [1, 2, 4, 5, 6].map(&:to_s) }) do |plan|
      pp plan.as_json
    end

    pp result.to_h
  end
end
