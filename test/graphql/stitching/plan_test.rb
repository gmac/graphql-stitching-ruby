# frozen_string_literal: true

require "test_helper"
require_relative "test_schemas/basic_graph"

class GraphQL::Stitching::PlanTest < Minitest::Test
  def setup
    puts "hello"
  end

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
    map = GraphQL::Stitching::Map.new(
      schema: ::BasicGraph::TestSchema,
      locations: ::BasicGraph::LOCATIONS_MAP,
      boundaries: ::BasicGraph::BOUNDARIES_MAP,
      fields: ::BasicGraph::FIELDS_MAP,
    )

    plan = GraphQL::Stitching::Plan.new(
      context: map,
      document: GraphQL.parse(QUERY),
    )

    byebug
  end
end
