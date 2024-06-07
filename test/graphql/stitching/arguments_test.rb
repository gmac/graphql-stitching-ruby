# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::ArgumentsTest < Minitest::Test
  include GraphQL::Stitching::Arguments

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

      field :scalar_key, Boolean, null: false do |f|
        f.argument(:key, ScalarKey)
      end

      field :builtin_scalar_key, Boolean, null: false do |f|
        f.argument(:key, String)
      end

      field :enum_key, Boolean, null: false do |f|
        f.argument(:key, TestEnum)
      end
    end

    query Query
  end

  def test_builds_single_object_key_into_matching_input_object
    args_schema = TestSchema.query.get_field("objectKey").arguments
    template = "key: {namespace: $.namespace, key: $.key, ownerType: $.ref.__typename, ownerId: $.ref.id}"
    expected = [Argument.new(
      name: "key",
      type_name: "ObjectKey",
      list: false,
      value: ObjectValue.new([
        Argument.new(
          name: "namespace",
          type_name: "String",
          value: KeyValue.new(["namespace"]),
        ),
        Argument.new(
          name: "key",
          type_name: "String",
          value: KeyValue.new(["key"]),
        ),
        Argument.new(
          name: "ownerType",
          type_name: "String",
          value: KeyValue.new(["ref", "__typename"]),
        ),
        Argument.new(
          name: "ownerId",
          type_name: "String",
          value: KeyValue.new(["ref", "id"]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Arguments.parse(args_schema, template)
  end

  def test_builds_object_list_key_into_matching_input_object
    args_schema = TestSchema.query.get_field("objectListKey").arguments
    template = "keys: {namespace: $.namespace, key: $.key}"
    expected = [Argument.new(
      name: "keys",
      type_name: "ObjectKey",
      list: true,
      value: ObjectValue.new([
        Argument.new(
          name: "namespace",
          type_name: "String",
          value: KeyValue.new(["namespace"]),
        ),
        Argument.new(
          name: "key",
          type_name: "String",
          value: KeyValue.new(["key"]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Arguments.parse(args_schema, template)
  end

  def test_builds_object_into_custom_scalar
    args_schema = TestSchema.query.get_field("scalarKey").arguments
    template = "key: {namespace: $.namespace, key: $.key}"
    expected = [Argument.new(
      name: "key",
      type_name: "ScalarKey",
      list: false,
      value: ObjectValue.new([
        Argument.new(
          name: "namespace",
          type_name: nil,
          value: KeyValue.new(["namespace"]),
        ),
        Argument.new(
          name: "key",
          type_name: nil,
          value: KeyValue.new(["key"]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Arguments.parse(args_schema, template)
  end

  def test_errors_for_building_objects_into_builtin_scalars
    args_schema = TestSchema.query.get_field("builtinScalarKey").arguments
    template = "key: {namespace: $.namespace, key: $.key}"

    assert_error "can only be built into custom scalar types" do
      GraphQL::Stitching::Arguments.parse(args_schema, template)
    end
  end

  def test_errors_for_building_objects_into_non_object_non_scalars
    args_schema = TestSchema.query.get_field("enumKey").arguments
    template = "key: {namespace: $.namespace, key: $.key}"

    assert_error "can only be built into input object and scalar positions" do
      GraphQL::Stitching::Arguments.parse(args_schema, template)
    end
  end

  def test_errors_for_building_invalid_root_keys
    args_schema = TestSchema.query.get_field("objectKey").arguments
    template = "key: {namespace: $.namespace, key: $.key}, invalid: true"

    assert_error "`invalid` is not a valid argument" do
      GraphQL::Stitching::Arguments.parse(args_schema, template)
    end
  end

  def test_errors_for_building_invalid_object_keys
    args_schema = TestSchema.query.get_field("objectKey").arguments
    template = "key: {namespace: $.namespace, key: $.key, invalid: true}"

    assert_error "`invalid` is not a valid argument" do
      GraphQL::Stitching::Arguments.parse(args_schema, template)
    end
  end

  def test_errors_for_omitting_a_required_root_argument
    args_schema = TestSchema.query.get_field("objectKey").arguments
    template = "other: true"

    assert_error "missing argument `key`" do
      GraphQL::Stitching::Arguments.parse(args_schema, template)
    end
  end

  def test_errors_for_omitting_a_required_object_argument
    args_schema = TestSchema.query.get_field("objectKey").arguments
    template = "key: {namespace: $.namespace}"

    assert_error "missing argument `key`" do
      GraphQL::Stitching::Arguments.parse(args_schema, template)
    end
  end
end
