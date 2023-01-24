# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::Compose::MergeScalarTest < Minitest::Test

  def test_merges_scalar_descriptions
    a = %{"""a""" scalar URL type Query { url:URL }}
    b = %{"""b""" scalar URL type Query { url:URL }}

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", schema.types["URL"].description
  end
end
