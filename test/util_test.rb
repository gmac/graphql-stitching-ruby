# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::UtilTest < Minitest::Test
  class TestSchema < GraphQL::Schema
    module TestInterface
      include GraphQL::Schema::Interface
      field :id, ID, null: false
    end

    class TestObject < GraphQL::Schema::Object
      implements TestInterface
    end

    class TestEnum < GraphQL::Schema::Enum
      value "YES"
    end

    class Query < GraphQL::Schema::Object
      field :list1, [String, null: true], null: false
      field :list2, [String, null: false], null: true
      field :list3, [[Int, null: true], null: false], null: true
      field :list4, [[Int, null: false], null: true], null: false
      field :the_object, TestObject, null: false
      field :the_enum, TestEnum, null: false
    end

    query Query
  end

  Util = GraphQL::Stitching::Util

  def test_get_named_type
    assert_equal "String", Util.get_named_type(field_type("list1")).graphql_name
    assert_equal "Int", Util.get_named_type(field_type("list3")).graphql_name
  end

  def test_get_list_structure
    assert_equal [:list, :element], Util.get_list_structure(field_type("list1"))
    assert_equal [:list, :non_null_element], Util.get_list_structure(field_type("list2"))
    assert_equal [:list, :non_null_list, :element], Util.get_list_structure(field_type("list3"))
    assert_equal [:list, :list, :non_null_element], Util.get_list_structure(field_type("list4"))
  end

  def test_is_leaf_type
    assert_equal true, Util.is_leaf_type?(TestSchema.get_type("String"))
    assert_equal true, Util.is_leaf_type?(TestSchema.get_type("TestEnum"))
    assert_equal false, Util.is_leaf_type?(TestSchema.get_type("TestObject"))
    assert_equal false, Util.is_leaf_type?(TestSchema.get_type("TestInterface"))
  end

  private

  def field_type(name)
    TestSchema.query.fields[name].type
  end
end
