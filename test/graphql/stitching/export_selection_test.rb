# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::ExportSelection" do
  def test_identifies_selection_hint_keys
    assert GraphQL::Stitching::ExportSelection.key?("_export_beep")
    assert GraphQL::Stitching::ExportSelection.key?("_export___typename")

    assert_equal false, GraphQL::Stitching::ExportSelection.key?("beep")
    assert_equal false, GraphQL::Stitching::ExportSelection.key?("__typename")
    assert_equal false, GraphQL::Stitching::ExportSelection.key?(nil)
  end

  def test_builds_selection_hint_keys
    assert_equal "_export_beep", GraphQL::Stitching::ExportSelection.key("beep")
  end

  def test_builds_selection_hint_nodes
    node = GraphQL::Stitching::ExportSelection.key_node("beep")
    assert_equal "_export_beep", node.alias
    assert_equal "beep", node.name
  end

  def test_provides_typename_hint_node
    node = GraphQL::Stitching::ExportSelection.typename_node
    assert_equal "_export___typename", node.alias
    assert_equal "__typename", node.name
  end
end
