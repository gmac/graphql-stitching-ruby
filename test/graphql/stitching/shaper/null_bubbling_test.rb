# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Shaper, null bubbling" do
  def test_basic_object_structure
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => {
        "req" => "yes",
        "opt" => nil
      }
    }
    expected = {
      "test" => {
        "req" => "yes",
        "opt" => nil
      }
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubbles_null_for_single_object_scopes
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => {
        "req" => nil,
        "opt" => "yes"
      }
    }
    expected = { "test" => nil }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubbles_null_for_recursive_object_scopes
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test! }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => {
        "req" => nil,
        "opt" => "yes"
      }
    }

    assert_nil GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_basic_list_structure
    schema_sdl = "type Test { req: String! opt: String } type Query { test: [Test] }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => [
        { "req" => "yes", "opt" => nil },
        { "req" => "yes", "opt" => "yes" },
      ]
    }
    expected = {
      "test" => [
        { "req" => "yes", "opt" => nil },
        { "req" => "yes", "opt" => "yes" },
      ]
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubbles_null_for_list_elements
    schema_sdl = "type Test { req: String! opt: String } type Query { test: [Test] }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => [
        { "req" => "yes", "opt" => nil },
        { "req" => nil, "opt" => "yes" },
      ]
    }
    expected = {
      "test" => [
        { "req" => "yes", "opt" => nil },
        nil,
      ]
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubbles_null_for_required_list_elements
    schema_sdl = "type Test { req: String! opt: String } type Query { test: [Test!] }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => [
        { "req" => "yes", "opt" => nil },
        { "req" => nil, "opt" => "yes" },
      ]
    }
    expected = {
      "test" => nil,
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubbles_null_for_required_lists
    schema_sdl = "type Test { req: String! opt: String } type Query { test: [Test!]! }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => [
        { "req" => "yes", "opt" => nil },
        { "req" => nil, "opt" => "yes" },
      ]
    }

    assert_nil GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_basic_nested_list_structure
    schema_sdl = "type Test { req: String! opt: String } type Query { test: [[Test]] }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => [
        [{ "req" => "yes", "opt" => nil }],
        [{ "req" => "yes", "opt" => "yes" }],
      ]
    }
    expected = {
      "test" => [
        [{ "req" => "yes", "opt" => nil }],
        [{ "req" => "yes", "opt" => "yes" }],
      ]
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubbles_null_for_nested_list_elements
    schema_sdl = "type Test { req: String! opt: String } type Query { test: [[Test]] }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => [
        [{ "req" => "yes", "opt" => nil }],
        [{ "req" => nil, "opt" => "yes" }],
      ]
    }
    expected = {
      "test" => [
        [{ "req" => "yes", "opt" => nil }],
        [nil],
      ]
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubbles_null_for_nested_required_list_elements
    schema_sdl = "type Test { req: String! opt: String } type Query { test: [[Test!]] }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => [
        [{ "req" => "yes", "opt" => nil }],
        [{ "req" => nil, "opt" => "yes" }],
      ]
    }
    expected = {
      "test" => [
        [{ "req" => "yes", "opt" => nil }],
        nil,
      ]
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubbles_null_for_inner_required_lists
    schema_sdl = "type Test { req: String! opt: String } type Query { test: [[Test!]!] }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => [
        [{ "req" => "yes", "opt" => nil }],
        [{ "req" => nil, "opt" => "yes" }],
      ]
    }
    expected = {
      "test" => nil
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubbles_null_through_nested_required_list_scopes
    schema_sdl = "type Test { req: String! opt: String } type Query { test: [[Test!]!]! }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { req opt } }|,
    )
    raw = {
      "test" => [
        [{ "req" => "yes", "opt" => nil }],
        [{ "req" => nil, "opt" => "yes" }],
      ]
    }

    assert_nil GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubble_through_inline_fragment
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    query = %|
      query {
        test {
          ... on Test {
            ... { req opt }
          }
        }
      }
    |
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      query,
    )
    raw = {
      "test" => {
        "_export___typename" => "Test",
        "req" => nil,
        "opt" => nil
      }
    }
    expected = {
      "test" => nil
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end

  def test_bubble_through_fragment_spreads
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    query = %|
      query { test { ...Test2 } }
      fragment Test1 on Test { req opt }
      fragment Test2 on Test { ...Test1 }
    |
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      query,
    )
    raw = {
      "test" => {
        "_export___typename" => "Test",
        "req" => nil,
        "opt" => nil
      }
    }
    expected = {
      "test" => nil
    }

    assert_equal expected, GraphQL::Stitching::Shaper.new(request).perform!(raw)
  end
end
