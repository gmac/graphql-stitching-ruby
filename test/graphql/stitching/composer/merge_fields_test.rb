# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging object and interface fields' do

  def test_merges_field_descriptions
    a = %{type Test { """a""" field: String } type Query { test:Test }}
    b = %{type Test { """b""" field: String } type Query { test:Test }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.types["Test"].fields["field"].description
  end

  def test_merges_field_deprecations
    a = %{type Test { field: String @deprecated(reason:"a") } type Query { test:Test }}
    b = %{type Test { field: String @deprecated(reason:"b") } type Query { test:Test }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      deprecation_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.types["Test"].fields["field"].deprecation_reason
  end

  def test_merged_fields_use_common_nullability
    a = "type Test { field: String! } type Query { test:Test }"
    b = "type Test { field: String! } type Query { test:Test }"

    info = compose_definitions({ "a" => a, "b" => b })
    assert_equal "String!", print_value_type(info.schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_use_weakest_nullability
    a = "type Test { field: String! } type Query { test:Test }"
    b = "type Test { field: String } type Query { test:Test }"

    info = compose_definitions({ "a" => a, "b" => b })
    assert_equal "String", print_value_type(info.schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_must_have_matching_named_types
    a = "type Test { field: String } type Query { test:Test }"
    b = "type Test { field: Int } type Query { test:Test }"

    # @todo verify error!
    assert_raises do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_fields_use_common_list_structure
    a = "type Test { field: [String!]! } type Query { test:Test }"
    b = "type Test { field: [String!]! } type Query { test:Test }"

    info = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[String!]!", print_value_type(info.schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_use_weakest_list_structure
    a = "type Test { field: [String!]! } type Query { test:Test }"
    b = "type Test { field: [String!] } type Query { test:Test }"
    c = "type Test { field: [String]! } type Query { test:Test }"

    info = compose_definitions({ "a" => a, "b" => b, "c" => c })
    assert_equal "[String]", print_value_type(info.schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_allow_deep_list_structures
    a = "type Test { field: [[String!]!]! } type Query { test:Test }"
    b = "type Test { field: [[String]!] } type Query { test:Test }"

    info = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[[String]!]", print_value_type(info.schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_must_have_matching_list_structures
    a = "type Test { field: [[String!]] } type Query { test:Test }"
    b = "type Test { field: [String!] } type Query { test:Test }"

    # @todo verify error!
    assert_raises do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  # @todo - test delegation maps
  def test_creates_delegation_map

  end
end
