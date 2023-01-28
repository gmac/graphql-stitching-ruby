# frozen_string_literal: true

require "test_helper"
require_relative "../../test_schema/sample"

describe 'GraphQL::Stitching::Plan, make it work' do

  QUERY = "
    query ($var:ID!){
      storefront(id: $var) {
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

  # def test_works
  #   subschemas = {
  #     "products" => TestSchema::Sample::Products,
  #     "storefronts" => TestSchema::Sample::Storefronts,
  #     "manufacturers" => TestSchema::Sample::Manufacturers,
  #   }

  #   graph_info = compose_definitions(subschemas)
  #   graph_info.add_client do |document, variables, location|
  #     schema = subschemas[location]
  #     schema.execute(document, variables: variables).to_h
  #   end

  #   plan = GraphQL::Stitching::Plan.new(
  #     graph_info: graph_info,
  #     document: GraphQL.parse(QUERY),
  #   ).plan

  #   result = GraphQL::Stitching::Execute.new(
  #     graph_info: graph_info,
  #     plan: plan.as_json,
  #     variables: { "var" => "1", "handle" => { "handle" => "woof" } }
  #   ).perform

  #   byebug
  # end

  def test_plan_abstract_merged_types
    a = "
      type Apple { id: ID! a: String }
      type Banana { id: ID! a: String }
      union Fruit = Apple | Banana
      type Query {
        fruit: Fruit
        apple(id: ID!): Apple @boundary(key: \"id\")
        banana(id: ID!): Banana @boundary(key: \"id\")
      }
    "
    b = "
      type Apple { id: ID! b: String }
      type Banana { id: ID! b: String }
      type Query {
        apple(id: ID!): Apple @boundary(key: \"id\")
        banana(id: ID!): Banana @boundary(key: \"id\")
      }
    "
    c = "
      type Apple { id: ID! c: String }
      type Coconut { id: ID! c: String }
      union Fruit = Apple | Coconut
      type Query {
        apple(id: ID!): Apple @boundary(key: \"id\")
        coconut(id: ID!): Coconut @boundary(key: \"id\")
      }
    "

    query = "{ fruit { ...on Apple { a b c } ...on Banana { a b } ...on Coconut { c } } }"

    graph_info = compose_definitions({ "a" => a, "b" => b, "c" => c })
    plan = GraphQL::Stitching::Plan.new(
      graph_info: graph_info,
      document: GraphQL.parse(query),
    ).plan

    pp plan.as_json
  end
end
