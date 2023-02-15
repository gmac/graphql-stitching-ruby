# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/introspection"

describe "GraphQL::Stitching::Shaper, grooming" do
  def test_prunes_stitching_fields
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    shaper = GraphQL::Stitching::Shaper.new(
      schema: GraphQL::Schema.from_definition(schema_sdl),
      request: GraphQL::Stitching::Request.new("{ test { __typename req opt } }"),
    )
    raw = {
      "data" => {
        "test" => {
          "_STITCH_req" => "yes",
          "_STITCH_typename" => "Test",
          "__typename" => "Test",
          "req" => "yes",
          "opt" => nil,
        }
      }
    }
    expected = {
      "data" => {
        "test" => {
          "__typename" => "Test",
          "req" => "yes",
          "opt" => nil,
        }
      }
    }

    assert_equal expected, shaper.perform!(raw)
  end

  def test_adds_missing_fields
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    shaper = GraphQL::Stitching::Shaper.new(
      schema: GraphQL::Schema.from_definition(schema_sdl),
      request: GraphQL::Stitching::Request.new("{ test { req opt } }"),
    )
    raw = {
      "data" => {
        "test" => {
          "_STITCH_req" => "yes",
          "_STITCH_typename" => "Test",
          "req" => "yes",
        }
      }
    }
    expected = {
      "data" => {
        "test" => {
          "req" => "yes",
          "opt" => nil,
        }
      }
    }

    assert_equal expected, shaper.perform!(raw)
  end

  def test_grooms_through_inline_fragments
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    shaper = GraphQL::Stitching::Shaper.new(
      schema: GraphQL::Schema.from_definition(schema_sdl),
      request: GraphQL::Stitching::Request.new("{ test { ... on Test { ... on Test { req opt } } } }"),
    )
    raw = {
      "data" => {
        "test" => {
          "_STITCH_req" => "yes",
          "_STITCH_typename" => "Test",
          "req" => "yes",
        }
      }
    }
    expected = {
      "data" => {
        "test" => {
          "req" => "yes",
          "opt" => nil,
        }
      }
    }

    assert_equal expected, shaper.perform!(raw)
  end

  def test_grooms_through_fragment_spreads
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    query = <<~GRAPHQL
      query { test { ...Test2 } }
      fragment Test1 on Test { req opt }
      fragment Test2 on Test { ...Test1 }
    GRAPHQL
    shaper = GraphQL::Stitching::Shaper.new(
      schema: GraphQL::Schema.from_definition(schema_sdl),
      request: GraphQL::Stitching::Request.new(query),
    )
    raw = {
      "data" => {
        "test" => {
          "_STITCH_req" => "yes",
          "_STITCH_typename" => "Test",
          "req" => "yes",
        }
      }
    }
    expected = {
      "data" => {
        "test" => {
          "req" => "yes",
          "opt" => nil,
        }
      }
    }

    assert_equal expected, shaper.perform!(raw)
  end

  def test_handles_introspection_types
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    schema = GraphQL::Schema.from_definition(schema_sdl)
    shaper = GraphQL::Stitching::Shaper.new(
      request: GraphQL::Stitching::Request.new(INTROSPECTION_QUERY),
      schema: schema,
    )

    raw = schema.execute(query: INTROSPECTION_QUERY).to_h
    assert shaper.perform!(raw)
  end
end
