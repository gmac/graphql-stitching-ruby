# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/example"
# require_relative "../../test_schema/unions"

describe 'GraphQL::Stitching::Planner, make it work' do

  # def test_plan_abstract_merged_types
  #   widgets = "
  #     type Widget { id:ID! }
  #     type Query { widget(id: ID!): Widget }
  #     type Mutation { makeWidget(id: ID!): Widget }
  #   "
  #   sprockets = "
  #     type Sprocket { id:ID! }
  #     type Query { sprocket(id: ID!): Sprocket }
  #     type Mutation { makeSprocket(id: ID!): Sprocket }
  #   "

  #   supergraph = compose_definitions({ "widgets" => widgets, "sprockets" => sprockets })
  # end

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
  #     "products" => Schemas::Example::Products,
  #     "storefronts" => Schemas::Example::Storefronts,
  #     "manufacturers" => Schemas::Example::Manufacturers,
  #   }

  #   supergraph = compose_definitions(subschemas)

  #   plan = GraphQL::Stitching::Planner.new(
  #     supergraph: supergraph,
  #     document: GraphQL.parse(QUERY),
  #   ).perform

  #   result = GraphQL::Stitching::Executor.new(
  #     supergraph: supergraph,
  #     plan: plan.as_json,
  #     variables: { "var" => "1" }
  #   ).perform

  #   byebug
  # end

  # def test_plan_abstract_merged_types
  #   a = "
  #     type Apple { id: ID! a: String }
  #     type Banana { id: ID! a: String }
  #     union Fruit = Apple | Banana
  #     type Query {
  #       fruit: Fruit
  #       apple(id: ID!): Apple @boundary(key: \"id\")
  #       banana(id: ID!): Banana @boundary(key: \"id\")
  #     }
  #   "
  #   b = "
  #     type Apple { id: ID! b: String }
  #     type Banana { id: ID! b: String }
  #     type Query {
  #       apple(id: ID!): Apple @boundary(key: \"id\")
  #       banana(id: ID!): Banana @boundary(key: \"id\")
  #     }
  #   "
  #   c = "
  #     type Apple { id: ID! c: String }
  #     type Coconut { id: ID! c: String }
  #     union Fruit = Apple | Coconut
  #     type Query {
  #       apple(id: ID!): Apple @boundary(key: \"id\")
  #       coconut(id: ID!): Coconut @boundary(key: \"id\")
  #     }
  #   "

  #   query = "{ fruit { ...on Apple { a b c } ...on Banana { a b } ...on Coconut { c } } }"

  #   supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c })
  #   plan = GraphQL::Stitching::Planner.new(
  #     supergraph: supergraph,
  #     document: GraphQL.parse(query),
  #   ).perform

  #   pp plan.as_json
  # end


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
  #     plan: plan.as_json,
  #   ).perform

  #   # pp plan.as_json
  #   pp result
  # end
end
