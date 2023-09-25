# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::SelectionHint" do
  def test_identifies_selection_hint_keys
    assert GraphQL::Stitching::SelectionHint.key?("_STITCH_beep")
    assert GraphQL::Stitching::SelectionHint.key?("_STITCH_typename")

    assert_equal false, GraphQL::Stitching::SelectionHint.key?("beep")
    assert_equal false, GraphQL::Stitching::SelectionHint.key?("__typename")
    assert_equal false, GraphQL::Stitching::SelectionHint.key?(nil)
  end

  def test_builds_selection_hint_keys
    assert_equal "_STITCH_beep", GraphQL::Stitching::SelectionHint.key("beep")
  end

  def test_builds_selection_hint_nodes
    node = GraphQL::Stitching::SelectionHint.key_node("beep")
    assert_equal "_STITCH_beep", node.alias
    assert_equal "beep", node.name
  end

  def test_provides_typename_hint_key
    assert_equal "_STITCH_typename", GraphQL::Stitching::SelectionHint.typename_key
  end

  def test_provides_typename_hint_node
    node = GraphQL::Stitching::SelectionHint.typename_node
    assert_equal "_STITCH_typename", node.alias
    assert_equal "__typename", node.name
  end
end
