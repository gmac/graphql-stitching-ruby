# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::Compose::MergeArgumentsTest < Minitest::Test

  ComposeError = GraphQL::Stitching::Compose::ComposeError

  def test_merged_arguments_use_common_nullability
    a = "input Test { arg:Int! } type Query { test(arg:Test!):Int }"
    b = "input Test { arg:Int! } type Query { test(arg:Test!):Int }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "Int!", print_value_type(schema.types["Test"].arguments["arg"].type)
    assert_equal "Test!", print_value_type(schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_arguments_use_strongest_nullability
    a = "input Test { arg:Int! } type Query { test(arg:Test):Int }"
    b = "input Test { arg:Int } type Query { test(arg:Test!):Int }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "Int!", print_value_type(schema.types["Test"].arguments["arg"].type)
    assert_equal "Test!", print_value_type(schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_object_arguments_must_have_matching_named_types
    a = "input Test { arg:Int } type Query { test(arg:Test):String }"
    b = "input Test { arg:String } type Query { test(arg:Test):String }"

    assert_error('Cannot compose mixed types at `Test.arg`', ComposeError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_field_arguments_must_have_matching_named_types
    a = "type Query { test(arg:Int):String }"
    b = "type Query { test(arg:String):String }"

    assert_error('Cannot compose mixed types at `Query.test.arg`', ComposeError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_arguments_use_common_list_structure
    a = "input Test { arg:[String!]! } type Query { test(arg:[Test!]!):String }"
    b = "input Test { arg:[String!]! } type Query { test(arg:[Test!]!):String }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[String!]!", print_value_type(schema.types["Test"].arguments["arg"].type)
    assert_equal "[Test!]!", print_value_type(schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_arguments_use_strongest_list_structure
    a = "input Test { arg:[String!] } type Query { test(arg:[Test]!):String }"
    b = "input Test { arg:[String]! } type Query { test(arg:[Test!]):String }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[String!]!", print_value_type(schema.types["Test"].arguments["arg"].type)
    assert_equal "[Test!]!", print_value_type(schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_arguments_allow_deep_list_structures
    a = "input Test { arg:[[String!]!]! } type Query { test(arg:[[Test!]!]!):String }"
    b = "input Test { arg:[[String]!] } type Query { test(arg:[[Test]!]):String }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[[String!]!]!", print_value_type(schema.types["Test"].arguments["arg"].type)
    assert_equal "[[Test!]!]!", print_value_type(schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_object_arguments_must_have_matching_list_structures
    a = "input Test { arg:[[String!]] } type Query { test:Test }"
    b = "input Test { arg:[String!] } type Query { test:Test }"

    assert_error('Cannot compose mixed list structures at `Test.arg`.', ComposeError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_field_arguments_must_have_matching_list_structures
    a = "type Query { test(arg:[String]):String }"
    b = "type Query { test(arg:[[String]]):String }"

    assert_error('Cannot compose mixed list structures at `Query.test.arg`.', ComposeError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merges_argument_descriptions
    a = %{input Test { """a""" arg:String } type Query { test("""a""" arg:Test):String }}
    b = %{input Test { """b""" arg:String } type Query { test("""b""" arg:Test):String }}

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", schema.types["Test"].arguments["arg"].description
    assert_equal "a/b", schema.types["Query"].fields["test"].arguments["arg"].description
  end

  def test_merges_field_deprecations
    a = %{input Test { arg:String @deprecated(reason:"a") } type Query { test(arg:Test @deprecated(reason:"a")):String }}
    b = %{input Test { arg:String @deprecated(reason:"b") } type Query { test(arg:Test @deprecated(reason:"b")):String }}

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b }, {
      deprecation_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", schema.types["Test"].arguments["arg"].deprecation_reason
    assert_equal "a/b", schema.types["Query"].fields["test"].arguments["arg"].deprecation_reason
  end

  # def test_creates_delegation_map

  # end
end
