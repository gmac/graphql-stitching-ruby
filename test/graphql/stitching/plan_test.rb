# frozen_string_literal: true

require "test_helper"
require_relative "../../test_schema/sample"

describe 'GraphQL::Stitching::Plan, make it work' do

  QUERY = "
    query {
      storefront(id: 1) {
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
        ...on Storefront { name }
        ...SfAttrs
      }
    }
    fragment SfAttrs on Storefront {
      name
    }
  "

  def test_works
    info = compose_definitions({
      "products" => TestSchema::Sample::Products,
      "storefronts" => TestSchema::Sample::Storefronts,
      "manufacturers" => TestSchema::Sample::Manufacturers,
    })

    plan = GraphQL::Stitching::Plan.new(
      graph_info: info,
      document: GraphQL.parse(QUERY),
    ).plan

    byebug
  end
end
