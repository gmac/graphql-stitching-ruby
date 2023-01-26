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
    subschemas = {
      "products" => TestSchema::Sample::Products,
      "storefronts" => TestSchema::Sample::Storefronts,
      "manufacturers" => TestSchema::Sample::Manufacturers,
    }

    info = compose_definitions(subschemas)

    plan = GraphQL::Stitching::Plan.new(
      graph_info: info,
      document: GraphQL.parse(QUERY),
    ).plan

    executor = GraphQL::Stitching::Execute.new(graph_info: info, plan: plan.as_json)
    executor.on_exec do |location, operation, variables|
      schema = subschemas[location]
      schema.execute(operation, variables: variables).to_h
    end

    result = executor.perform

    byebug
  end
end
