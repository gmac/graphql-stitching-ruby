# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Composer, expand abstract type" do
  class ExpandAbstractTypeTestSchema < GraphQL::Schema
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

    class TestUnion < GraphQL::Schema::Union
      possible_types FirstObject, SecondObject
    end

    class Query < GraphQL::Schema::Object
      field :first, FirstObject, null: false
      field :second, SecondObject, null: false
      field :the_union, TestUnion, null: false
    end

    query Query
  end

  def test_expand_interface
    result = composer.expand_abstract_type(schema, schema.get_type("ParentInterface"))
    assert_equal ["ChildInterface", "FirstObject", "SecondObject"], result.map(&:graphql_name).sort

    result = composer.expand_abstract_type(schema, schema.get_type("ChildInterface"))
    assert_equal ["SecondObject"], result.map(&:graphql_name).sort
  end

  def test_expand_union
    result = composer.expand_abstract_type(schema, schema.get_type("TestUnion"))
    assert_equal ["FirstObject", "SecondObject"], result.map(&:graphql_name).sort
  end

  def test_expand_non_abstract
    result = composer.expand_abstract_type(schema, schema.get_type("String"))
    assert_equal [], result.map(&:graphql_name).sort
  end

  private

  def composer
    GraphQL::Stitching::Composer.new
  end

  def schema
    ExpandAbstractTypeTestSchema
  end
end
