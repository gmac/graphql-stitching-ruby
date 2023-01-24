# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::Compose::MergeEnumTest < Minitest::Test

  def test_merges_enum_and_value_descriptions
    a = %{"""a""" enum Status { """a""" YES } type Query { status:Status }}
    b = %{"""b""" enum Status { """b""" YES } type Query { status:Status }}

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", schema.types["Status"].description
    assert_equal "a/b", schema.types["Status"].values["YES"].description
  end

  def test_merges_enum_values_using_union_when_readonly
    a = %{enum Status { YES NO } type Query { status:Status }}
    b = %{enum Status { YES NO MAYBE } type Query { status:Status }}

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["MAYBE", "NO", "YES"], schema.types["Status"].values.keys.sort
  end

  def test_merges_enum_values_using_intersection_when_input_via_field_arg
    a = %{enum Status { YES NO } type Query { status1:Status }}
    b = %{enum Status { YES NO MAYBE } type Query { status2(s:Status):Status }}

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["NO", "YES"], schema.types["Status"].values.keys.sort
  end

  def test_merges_enum_values_using_intersection_when_input_via_object
    a = %{enum Status { YES NO } input MyStatus { status:Status } type Query { status1(s:MyStatus):Status }}
    b = %{enum Status { YES NO MAYBE } type Query { status:Status }}

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["NO", "YES"], schema.types["Status"].values.keys.sort
  end
end
