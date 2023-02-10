# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Shaper, grooming" do
  def test_prunes_stitching_fields
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    shaper = GraphQL::Stitching::Shaper.new(
      schema: GraphQL::Schema.from_definition(schema_sdl),
      document: GraphQL::Stitching::Document.new("{ test { req opt } }"),
    )
    raw = {
      "data" => {
        "test" => {
          "_STITCH_req" => "yes",
          "_STITCH_typename" => "Test",
          "req" => "yes",
          "opt" => nil,
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

  def test_adds_missing_fields
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    shaper = GraphQL::Stitching::Shaper.new(
      schema: GraphQL::Schema.from_definition(schema_sdl),
      document: GraphQL::Stitching::Document.new("{ test { req opt } }"),
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
      document: GraphQL::Stitching::Document.new("{ test { ... on Test { ... on Test { req opt } } } }"),
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
      document: GraphQL::Stitching::Document.new(query),
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
end
