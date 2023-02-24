# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging object and field arguments' do

  def test_merged_arguments_use_common_nullability
    a = "input Test { arg:Int! } type Query { test(arg:Test!):Int }"
    b = "input Test { arg:Int! } type Query { test(arg:Test!):Int }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal "Int!", print_value_type(supergraph.schema.types["Test"].arguments["arg"].type)
    assert_equal "Test!", print_value_type(supergraph.schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_arguments_use_strongest_nullability
    a = "input Test { arg:Int! } type Query { test(arg:Test):Int }"
    b = "input Test { arg:Int } type Query { test(arg:Test!):Int }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal "Int!", print_value_type(supergraph.schema.types["Test"].arguments["arg"].type)
    assert_equal "Test!", print_value_type(supergraph.schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_object_arguments_must_have_matching_named_types
    a = "input Test { arg:Int } type Query { test(arg:Test):String }"
    b = "input Test { arg:String } type Query { test(arg:Test):String }"

    assert_error('Cannot compose mixed types at `Test.arg`', ComposerError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_field_arguments_must_have_matching_named_types
    a = "type Query { test(arg:Int):String }"
    b = "type Query { test(arg:String):String }"

    assert_error('Cannot compose mixed types at `Query.test.arg`', ComposerError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_arguments_use_common_list_structure
    a = "input Test { arg:[String!]! } type Query { test(arg:[Test!]!):String }"
    b = "input Test { arg:[String!]! } type Query { test(arg:[Test!]!):String }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[String!]!", print_value_type(supergraph.schema.types["Test"].arguments["arg"].type)
    assert_equal "[Test!]!", print_value_type(supergraph.schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_arguments_use_strongest_list_structure
    a = "input Test { arg:[String!] } type Query { test(arg:[Test]!):String }"
    b = "input Test { arg:[String]! } type Query { test(arg:[Test!]):String }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[String!]!", print_value_type(supergraph.schema.types["Test"].arguments["arg"].type)
    assert_equal "[Test!]!", print_value_type(supergraph.schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_arguments_allow_deep_list_structures
    a = "input Test { arg:[[String!]!]! } type Query { test(arg:[[Test!]!]!):String }"
    b = "input Test { arg:[[String]!] } type Query { test(arg:[[Test]!]):String }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[[String!]!]!", print_value_type(supergraph.schema.types["Test"].arguments["arg"].type)
    assert_equal "[[Test!]!]!", print_value_type(supergraph.schema.types["Query"].fields["test"].arguments["arg"].type)
  end

  def test_merged_object_arguments_must_have_matching_list_structures
    a = "input Test { arg:[[String!]] } type Query { test:Test }"
    b = "input Test { arg:[String!] } type Query { test:Test }"

    assert_error('Cannot compose mixed list structures at `Test.arg`.', ComposerError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_field_arguments_must_have_matching_list_structures
    a = "type Query { test(arg:[String]):String }"
    b = "type Query { test(arg:[[String]]):String }"

    assert_error('Cannot compose mixed list structures at `Query.test.arg`.', ComposerError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merges_argument_descriptions
    a = %{input Test { """a""" arg:String } type Query { test("""a""" arg:Test):String }}
    b = %{input Test { """b""" arg:String } type Query { test("""b""" arg:Test):String }}

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.types["Test"].arguments["arg"].description
    assert_equal "a/b", supergraph.schema.types["Query"].fields["test"].arguments["arg"].description
  end

  def test_merges_argument_deprecations
    a = %{input Test { arg:String @deprecated(reason:"a") } type Query { test(arg:Test @deprecated(reason:"a")):String }}
    b = %{input Test { arg:String @deprecated(reason:"b") } type Query { test(arg:Test @deprecated(reason:"b")):String }}

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      deprecation_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.types["Test"].arguments["arg"].deprecation_reason
    assert_equal "a/b", supergraph.schema.types["Query"].fields["test"].arguments["arg"].deprecation_reason
  end

  def test_merges_argument_directives
    a = <<~GRAPHQL
      directive @fizzbuzz(arg: String!) on ARGUMENT_DEFINITION
      type Query { test(arg:String @fizzbuzz(arg:"a")):String }
    GRAPHQL

    b = <<~GRAPHQL
      directive @fizzbuzz(arg: String!) on ARGUMENT_DEFINITION
      type Query { test(arg:String @fizzbuzz(arg:"b")):String }
    GRAPHQL

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    directive = supergraph.schema.types["Query"].fields["test"].arguments["arg"].directives.first
    assert_equal "a/b", directive.arguments.keyword_arguments[:arg]
  end

  def test_intersects_optional_arguments
    a = "input Test { arg1:String arg2:String } type Query { test(arg1:Test, arg2:String):String }"
    b = "input Test { arg3:String arg2:String } type Query { test(arg3:Test, arg2:String):String }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["arg2"], supergraph.schema.types["Test"].arguments.keys.sort
    assert_equal ["arg2"], supergraph.schema.types["Query"].fields["test"].arguments.keys.sort
  end

  def test_fails_to_merge_isolated_required_object_arguments
    a = "input Test { arg1:String! } type Query { test(arg:Test):String }"
    b = "input Test { arg2:String } type Query { test(arg:Test):String }"

    assert_error('Required argument `Test.arg1` must be defined in all locations.', ComposerError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_fails_to_merge_isolated_required_field_arguments
    a = "type Query { test(arg1:String):String }"
    b = "type Query { test(arg2:String!):String }"

    assert_error('Required argument `Query.test.arg2` must be defined in all locations.', ComposerError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end
end
