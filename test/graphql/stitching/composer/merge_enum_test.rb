# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging enums' do

  def test_merges_enum_and_value_descriptions
    a = %|"""a""" enum Status { """a""" YES } type Query { status:Status }|
    b = %|"""b""" enum Status { """b""" YES } type Query { status:Status }|

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      formatter: TestFormatter.new,
    })

    assert_equal "a/b", supergraph.schema.types["Status"].description
    assert_equal "a/b", supergraph.schema.types["Status"].values["YES"].description
  end

  def test_merges_enum_and_value_directives
    a = %|
      directive @fizzbuzz(arg: String!) on ENUM \| ENUM_VALUE
      enum Status @fizzbuzz(arg: "a") { YES @fizzbuzz(arg: "a") }
      type Query { status:Status }
    |

    b = %|
      directive @fizzbuzz(arg: String!) on ENUM \| ENUM_VALUE
      enum Status @fizzbuzz(arg: "b") { YES @fizzbuzz(arg: "b") }
      type Query { status:Status }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      formatter: TestFormatter.new,
    })

    assert_equal "a/b", supergraph.schema.types["Status"].directives.first.arguments.keyword_arguments[:arg]
    assert_equal "a/b", supergraph.schema.types["Status"].values["YES"].directives.first.arguments.keyword_arguments[:arg]
  end

  def test_merges_enum_values_using_union_when_readonly
    a = %|enum Status { YES NO } type Query { status:Status }|
    b = %|enum Status { YES NO MAYBE } type Query { status:Status }|

    supergraph = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["MAYBE", "NO", "YES"], supergraph.schema.types["Status"].values.keys.sort
  end

  def test_merges_enum_values_using_intersection_when_input_via_field_arg
    a = %|enum Status { YES NO } type Query { status1:Status }|
    b = %|enum Status { YES NO MAYBE } type Query { status2(s:Status):Status }|

    supergraph = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["NO", "YES"], supergraph.schema.types["Status"].values.keys.sort
  end

  def test_merges_enum_values_using_intersection_when_input_via_object
    a = %|enum Status { YES NO } input MyStatus { status:Status } type Query { status1(s:MyStatus):Status }|
    b = %|enum Status { YES NO MAYBE } type Query { status:Status }|

    supergraph = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["NO", "YES"], supergraph.schema.types["Status"].values.keys.sort
  end

  class SchemaAlpha < GraphQL::Schema
    class Toggle < GraphQL::Schema::Enum
      value("ON", value: "1")
      value("OFF", value: "0")
    end

    class Query < GraphQL::Schema::Object
      field :a, Toggle
    end
    query Query
  end

  class SchemaBravo < GraphQL::Schema
    class Toggle < GraphQL::Schema::Enum
      value("ON", value: true)
      value("OFF", value: false)
    end

    class Query < GraphQL::Schema::Object
      field :b, Toggle
    end
    query Query
  end

  def test_merges_class_based_enums_with_value_mappings
    supergraph = compose_definitions({ "a" => SchemaAlpha, "b" => SchemaBravo })

    assert_equal ["OFF", "ON"], supergraph.schema.types["Toggle"].values.keys.sort
    assert_equal ["OFF", "ON"], supergraph.schema.types["Toggle"].values.values.map(&:graphql_name).sort
    assert_equal ["OFF", "ON"], supergraph.schema.types["Toggle"].values.values.map(&:value).sort
  end
end
