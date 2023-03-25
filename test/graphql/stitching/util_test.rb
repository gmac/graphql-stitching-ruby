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

  def test_is_leaf_type
    assert_equal true, Util.is_leaf_type?(TestSchema.get_type("String"))
    assert_equal true, Util.is_leaf_type?(TestSchema.get_type("TestEnum"))
    assert_equal false, Util.is_leaf_type?(TestSchema.get_type("FirstObject"))
    assert_equal false, Util.is_leaf_type?(TestSchema.get_type("ParentInterface"))
    assert_equal false, Util.is_leaf_type?(TestSchema.get_type("TestUnion"))
  end

  def test_unwrap_non_null
    field = field_type("first")
    assert_equal true, field.non_null?
    assert_equal false, Util.unwrap_non_null(field).non_null?
    assert_equal "FirstObject", Util.unwrap_non_null(field).graphql_name
  end

  def test_unwrap_non_null_list
    field = field_type("list1")
    assert_equal true, field.non_null?
    assert_equal false, Util.unwrap_non_null(field).non_null?
    assert_equal "String", Util.unwrap_non_null(field).unwrap.graphql_name
  end

  def test_named_type_for_field_node_with_schema_field
    node = GraphQL.parse("{ first }").definitions.first.selections.first
    assert_equal "FirstObject", Util.type_for_field_node(TestSchema, TestSchema.query, node).unwrap.graphql_name
  end

  def test_named_type_for_field_node_with_introspection_field
    node = GraphQL.parse("{ __schema }").definitions.first.selections.first
    assert_equal "__Schema", Util.type_for_field_node(TestSchema, TestSchema.query, node).unwrap.graphql_name
  end

  def test_flatten_type_structure
    expected_list1 = [
      { list: true, null: false, name: nil },
      { list: false, null: true, name: "String" },
    ]
    assert_equal expected_list1, Util.flatten_type_structure(field_type("list1"))

    expected_list2 = [
      { list: true, null: true, name: nil },
      { list: false, null: false, name: "String" },
    ]
    assert_equal expected_list2, Util.flatten_type_structure(field_type("list2"))

    expected_list3 = [
      { list: true, null: true, name: nil },
      { list: true, null: false, name: nil },
      { list: false, null: true, name: "Int" },
    ]
    assert_equal expected_list3, Util.flatten_type_structure(field_type("list3"))

    expected_list4 = [
      { list: true, null: false, name: nil },
      { list: true, null: true, name: nil },
      { list: false, null: false, name: "Int" },
    ]
    assert_equal expected_list4, Util.flatten_type_structure(field_type("list4"))
  end

  def test_expand_abstract_type_for_interface
    result = Util.expand_abstract_type(TestSchema, TestSchema.get_type("ParentInterface"))
    assert_equal ["ChildInterface", "FirstObject", "SecondObject"], result.map(&:graphql_name).sort

    result = Util.expand_abstract_type(TestSchema, TestSchema.get_type("ChildInterface"))
    assert_equal ["SecondObject"], result.map(&:graphql_name).sort
  end

  def test_expand_abstract_type_for_union
    result = Util.expand_abstract_type(TestSchema, TestSchema.get_type("TestUnion"))
    assert_equal ["FirstObject", "SecondObject"], result.map(&:graphql_name).sort
  end

  def test_expand_abstract_type_for_non_abstract
    result = Util.expand_abstract_type(TestSchema, TestSchema.get_type("String"))
    assert_equal [], result.map(&:graphql_name).sort
  end

  private

  def field_type(name)
    TestSchema.query.fields[name].type
  end
end
