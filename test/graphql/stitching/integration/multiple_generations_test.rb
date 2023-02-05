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
  end

  def test_resolves_multiple_generations
    query = "
      query($id: ID!){
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
    "

    result = plan_and_execute(@supergraph, query, { "id" => "1" })

    # pp result
    # @todo validate shape once there's a resolver
    assert result.dig("data")
  end
end
