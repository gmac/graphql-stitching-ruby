# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/example"

describe "GraphQL::Stitching::Request" do

  SCHEMA_A = GraphQL::Schema.from_definition(<<~'GRAPHQL'.chomp)
    type Query {
      parentResource(id: ID!): ParentResource
      subResourcesByIds(ids: [ID!]!): [SubResource]!
    }

    type ParentResource {
      id: ID!
      subResource: SubResource
    }

    type SubResource {
      id: ID!
    }
  GRAPHQL


  SCHEMA_B = GraphQL::Schema.from_definition(<<~'GRAPHQL'.chomp)
    type Query {
      subResourcesByIds(ids: [ID!]!): [SubResource]!
    }

    type SubResource {
      id: ID!
      serviceBField: String!
    }
  GRAPHQL

  def test_mystery
    client = GraphQL::Stitching::Client.new(locations: {
      service_a: {
        schema: SCHEMA_A,
        executable: ->(req, source, vars) do
          puts source
        {
          "data" => {
            "parentResource" => {
              "id" => "ParentResource:1000",
              "_export___typename" => "ParentResource",
              "subResource" => {
                "id" => "SubResource:2000",
                "_export_id" => "SubResource:2000",
                "_export___typename" => "SubResource"
              },
            }
          }
        }
        end,
        stitch: [
          { field_name: "subResourcesByIds", key: "id" },
        ],
      },
      service_b_schema: {
        schema: SCHEMA_B,
        executable: ->(req, source, vars) do
          puts source
          {
            "data" => {
              "_0_result" => [nil]
            }
          }
        end,
        stitch: [
          { field_name: "subResourcesByIds", key: "id" },
        ],
      },
    })

    # "_export___typename" => "ParentResource",

    query_ok = <<~'QUERY'
      query {
        parentResource(id: "ParentResource:1000") {
          id
          subResource {
            ...SubResourceFragment
          }
        }
      }

      fragment SubResourceFragment on SubResource {
        id
        serviceBField
      }
    QUERY

    query_ng = <<~'QUERY'
      query {
        parentResource(id: "ParentResource:1000") {
          ...ParentResourceFragment
        }
      }

      fragment ParentResourceFragment on ParentResource {
        id
        subResource {
          id
          serviceBField
        }
      }
    QUERY

    # puts "First query..."
    # pp client.execute(query: query_ok)

    puts "Second query..."
    pp client.execute(query: query_ng)
  end
end
