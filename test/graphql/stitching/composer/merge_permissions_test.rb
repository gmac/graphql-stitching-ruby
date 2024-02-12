# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging permissions' do
  PermissionsMerger = GraphQL::Stitching::Composer::PermissionsMerger

  def test_merges_multiple_unique_permission_scopes
    result = PermissionsMerger.call({
      "alpha" => [["a", "b"], ["c"]],
      "bravo" => [["x", "y"], ["z"]],
      "delta" => [["q"]],
    })

    expected = [
      ["a", "b", "q", "x", "y"],
      ["a", "b", "q", "z"],
      ["c", "q", "x", "y"],
      ["c", "q", "z"],
    ]

    assert_equal expected, result
  end

  def test_merges_multiple_permission_scopes_with_duplicates
    result = PermissionsMerger.call({
      "alpha" => [["a", "b"], ["x"]],
      "bravo" => [["a", "c"], ["y"]],
    })

    expected = [
      ["a", "b", "c"],
      ["a", "b", "y"],
      ["a", "c", "x"],
      ["x", "y"],
    ]

    assert_equal expected, result
  end

  def test_merges_and_deduplicates_multiple_or_scopes
    result = PermissionsMerger.call({
      "alpha" => [["a", "b", "c"]],
      "bravo" => [["a"], ["b"], ["c"]],
    })

    expected = [
      ["a", "b", "c"],
    ]

    assert_equal expected, result
  end

  def test_merges_visibility_directive_scopes
    dir = "directive @visibility(scopes: [[String!]!], policies: [[String!]!]) on FIELD_DEFINITION"

    supergraph = compose_definitions({
      "a" => dir + %| type Query { test: String @visibility(scopes: [["a", "b"], ["c"]], policies: [["a", "b"]]) }|,
      "b" => dir + %| type Query { test: String @visibility(scopes: [["x"], ["y"]], policies: [["b", "c"]]) }|,
    })

    args = supergraph.schema.query.get_field("test").directives.first.arguments.keyword_arguments
    assert_equal [["a", "b", "x"], ["a", "b", "y"], ["c", "x"], ["c", "y"]], args[:scopes]
    assert_equal [["a", "b", "c"]], args[:policies]
  end
end
