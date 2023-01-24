# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::Compose::MergeInputObjectTest < Minitest::Test

  def test_merges_input_object_descriptions
    a = %{"""a""" input Test { field:String } type Query { get(test:Test):String }}
    b = %{"""b""" input Test { field:String } type Query { get(test:Test):String }}

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", schema.types["Test"].description
  end
end
