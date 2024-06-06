# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::ArgumentsTest < Minitest::Test
  class TestSchema < GraphQL::Schema
    class TestEnum < GraphQL::Schema::Enum
      value "YES"
    end

    class ObjectKey < GraphQL::Schema::InputObject
      graphql_name "ObjectKey"

      argument :namespace, String, required: true
      argument :key, String, required: true
      argument :owner_type, String, required: false
      argument :owner_id, String, required: false
    end

    class ScalarKey < GraphQL::Schema::Scalar
      graphql_name "ScalarKey"
    end

    class Query < GraphQL::Schema::Object
      field :object_key, Boolean, null: false do |f|
        f.argument(:key, ObjectKey)
      end

      field :object_list_key, [Boolean], null: false do |f|
        f.argument(:keys, [ObjectKey])
      end

      field :scalar_key, [Boolean], null: false do |f|
        f.argument(:key, ScalarKey)
      end
    end

    query Query
  end

  def test_single_object_key
    args_schema = TestSchema.query.get_field("objectKey").arguments
    template = "key: {namespace: $.namespace, key: $.key, ownerType: $.ref.__typename, ownerId: $.ref.id}"
    pp GraphQL::Stitching::Arguments.parse(args_schema, template).as_json
  end

  def test_object_list_key
    args_schema = TestSchema.query.get_field("objectListKey").arguments
    template = "keys: {namespace: $.namespace, key: $.key, ownerType: $.ref.__typename, ownerId: $.ref.id}"
    pp GraphQL::Stitching::Arguments.parse(args_schema, template).as_json
  end

  def test_scalar_key
    args_schema = TestSchema.query.get_field("scalarKey").arguments
    template = "key: {namespace: $.namespace, key: $.key, ownerType: $.ref.__typename, ownerId: $.ref.id}"
    # binding.pry
    pp GraphQL::Stitching::Arguments.parse(args_schema, template).as_json
  end
end
