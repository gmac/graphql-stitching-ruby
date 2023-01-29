# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::UtilTest < Minitest::Test
  class TestSchema < GraphQL::Schema
    module ParentInterface
      include GraphQL::Schema::Interface
      field :id, ID, null: false
    end

    module ChildInterface
      include GraphQL::Schema::Interface
      implements ParentInterface
    end

    class FirstObject < GraphQL::Schema::Object
      implements ParentInterface
    end

    class SecondObject < GraphQL::Schema::Object
      implements ChildInterface
    end

    class TestEnum < GraphQL::Schema::Enum
      value "YES"
    end

    class TestUnion < GraphQL::Schema::Union
      possible_types FirstObject, SecondObject
    end

    class Query < GraphQL::Schema::Object
      field :list1, [String, null: true], null: false
      field :list2, [String, null: false], null: true
      field :list3, [[Int, null: true], null: false], null: true
      field :list4, [[Int, null: false], null: true], null: false
      field :first, FirstObject, null: false
      field :second, SecondObject, null: false
      field :the_enum, TestEnum, null: false
      field :the_union, TestUnion, null: false
    end

    query Query
  end

  Util = GraphQL::Stitching::Util

  def test_get_named_type
    assert_equal "String", Util.get_named_type(field_type("list1")).graphql_name
    assert_equal "Int", Util.get_named_type(field_type("list3")).graphql_name
  end

  def test_get_list_structure
    assert_equal ["list", "element"], Util.get_list_structure(field_type("list1"))
    assert_equal ["list", "non_null_element"], Util.get_list_structure(field_type("list2"))
    assert_equal ["list", "non_null_list", "element"], Util.get_list_structure(field_type("list3"))
    assert_equal ["list", "list", "non_null_element"], Util.get_list_structure(field_type("list4"))
  end

  def test_get_possible_types_for_interface
    result = Util.get_possible_types(TestSchema, TestSchema.get_type("ParentInterface"))
    assert_equal ["ChildInterface", "FirstObject", "SecondObject"], result.map(&:graphql_name).sort

    result = Util.get_possible_types(TestSchema, TestSchema.get_type("ChildInterface"))
    assert_equal ["SecondObject"], result.map(&:graphql_name).sort
  end

  def test_get_possible_types_for_union
    result = Util.get_possible_types(TestSchema, TestSchema.get_type("TestUnion"))
    assert_equal ["FirstObject", "SecondObject"], result.map(&:graphql_name).sort
  end

  def test_get_possible_types_for_non_abstract_types
    ["FirstObject", "TestEnum", "String"].each do |type_name|
      result = Util.get_possible_types(TestSchema, TestSchema.get_type(type_name))
      assert_equal [type_name], result.map(&:graphql_name).sort
    end
  end

  def test_is_leaf_type
    assert_equal true, Util.is_leaf_type?(TestSchema.get_type("String"))
    assert_equal true, Util.is_leaf_type?(TestSchema.get_type("TestEnum"))
    assert_equal false, Util.is_leaf_type?(TestSchema.get_type("FirstObject"))
    assert_equal false, Util.is_leaf_type?(TestSchema.get_type("ParentInterface"))
  end

  private

  def field_type(name)
    TestSchema.query.fields[name].type
  end
end
