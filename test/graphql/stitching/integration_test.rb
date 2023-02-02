# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/example"
require_relative "../../schemas/interfaces"

describe 'GraphQL::Stitching, integration tests' do
  def test_queries_deeply_nested_locations
    supergraph = compose_definitions({
      "products" => Schemas::Example::Products,
      "storefronts" => Schemas::Example::Storefronts,
      "manufacturers" => Schemas::Example::Manufacturers,
    })

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

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL.parse(query),
    ).perform

    result = GraphQL::Stitching::Executor.new(
      supergraph: supergraph,
      plan: plan.to_h,
      variables: { "id" => "1" }
    ).perform

    # pp result
    # @todo validate shape once there's a resolver
    assert result.dig("data")
  end

  def test_queries_merged_interfaces
    supergraph = compose_definitions({
      "products" => Schemas::Interfaces::Products,
      "bundles" => Schemas::Interfaces::Bundles,
    })

    query = "
      query($ids: [ID!]!) {
        bundles(ids: $ids) {
          id
          name
          price
          products {
            id
            name
            price
          }
        }
      }
    "
    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL.parse(query),
    ).perform

    result = GraphQL::Stitching::Executor.new(
      supergraph: supergraph,
      plan: plan.to_h,
      variables: { "ids" => ["1"] }
    ).perform

    pp result

    bundle = result.dig("data", "bundles", 0)
    expected_root = { "id" => "1", "name" => "Apple Gear", "price" => 999.99 }
    expected_products = [
      { "id" => "1", "name" => "iPhone", "price" => 699.99 },
      { "id" => "2", "name" => "Apple Watch", "price" => 399.99 },
    ]

    # @todo make this cleaner once there's a resolver
    assert_equal expected_root, bundle.slice("id", "name", "price")
    assert_equal expected_products, bundle["products"].map { _1.slice("id", "name", "price") }
  end

  # def test_plan_abstract_merged_types
  #   schemas = {
  #     "a" => TestSchema::Unions::SchemaA,
  #     "b" => TestSchema::Unions::SchemaB,
  #     "c" => TestSchema::Unions::SchemaC,
  #   }

  #   supergraph = compose_definitions(schemas)
  #   supergraph.add_client do |document, variables, location|
  #      schemas[location].execute(document, variables: variables).to_h
  #   end

  #   query = "{ fruitsA(ids: [\"1\", \"3\"]) { ...on Apple { a b c } ...on Banana { a b } ...on Coconut { c } } }"

  #   plan = GraphQL::Stitching::Planner.new(
  #     supergraph: supergraph,
  #     document: GraphQL.parse(query),
  #   ).perform

  #   result = GraphQL::Stitching::Executor.new(
  #     supergraph: supergraph,
  #     plan: plan.to_h,
  #   ).perform

  #   # pp plan.to_h
  #   pp result
  # end
end
