# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::ComposeTest < Minitest::Test

  def test_merged_fields_use_common_nullability
    a = "type Test { field: String! } type Query { test:Test }"
    b = "type Test { field: String! } type Query { test:Test }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "String!", print_value_type(schema.types["Test"].fields["field"].type)
  end
end