# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching" do
  def test_schema_from_definition_adds_directives
    schema_sdl = <<~GRAPHQL
      type Product {
        id: ID!
        upc: ID!
      }
      type Query {
        productById(id: ID!): Product
        productByUpc(upc: ID!): Product
      }
    GRAPHQL

    schema = GraphQL::Stitching.schema_from_definition(schema_sdl, stitch_directives: [
      { type_name: "Query", field_name: "productById", key: "id" },
      { type_name: "Query", field_name: "productByUpc", key: "upc" },
    ])

    assert schema.directives[GraphQL::Stitching.stitch_directive]

    directive_with_id = schema.types["Query"].fields["productById"].directives.first
    assert_equal GraphQL::Stitching.stitch_directive, directive_with_id.graphql_name

    directive_with_upc = schema.types["Query"].fields["productByUpc"].directives.first
    assert_equal GraphQL::Stitching.stitch_directive, directive_with_upc.graphql_name
  end
end
