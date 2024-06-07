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

      argument :slug, String, required: true
      argument :namespace, String, required: false
      argument :nested, self, required: false
      argument :nested_list, [self], required: false
    end

    class ScalarKey < GraphQL::Schema::Scalar
      graphql_name "ScalarKey"
    end

    class Query < GraphQL::Schema::Object
      field :object_key, Boolean, null: false do |f|
        f.argument(:key, ObjectKey, required: true)
        f.argument(:other, String, required: false)
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

  def test_builds_flat_object_key_into_matching_input_object
    template = "key: {slug: $.slug, namespace: 'sfoo'}"
    expected = [Argument.new(
      name: "key",
      type_name: "ObjectKey",
      list: false,
      value: ObjectValue.new([
        Argument.new(
          name: "slug",
          type_name: "String",
          value: KeyValue.new(["slug"]),
        ),
        Argument.new(
          name: "namespace",
          type_name: "String",
          value: LiteralValue.new("sfoo"),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Arguments.parse(template, arg_defs("objectKey"))
  end

  def test_builds_nested_object_key_into_matching_input_objects
    template = "key: {slug: $.slug, nested:{slug: $.slug, namespace: 'sfoo'}}"
    expected = [Argument.new(
      name: "key",
      type_name: "ObjectKey",
      list: false,
      value: ObjectValue.new([
        Argument.new(
          name: "slug",
          type_name: "String",
          value: KeyValue.new(["slug"]),
        ),
        Argument.new(
          name: "nested",
          type_name: "ObjectKey",
          value: ObjectValue.new([
            Argument.new(
              name: "slug",
              type_name: "String",
              value: KeyValue.new(["slug"]),
            ),
            Argument.new(
              name: "namespace",
              type_name: "String",
              value: LiteralValue.new("sfoo"),
            ),
          ]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Arguments.parse(template, arg_defs("objectKey"))
  end

  def test_builds_nested_key_paths
    template = "key: {slug: $.ref.slug}"
    expected = [Argument.new(
      name: "key",
      type_name: "ObjectKey",
      list: false,
      value: ObjectValue.new([
        Argument.new(
          name: "slug",
          type_name: "String",
          value: KeyValue.new(["ref", "slug"]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Arguments.parse(template, arg_defs("objectKey"))
  end

  def test_builds_object_list_keys_into_matching_inputs
    template = "keys: {slug: $.slug, nestedList: {slug: $.ref.slug}}"
    expected = [Argument.new(
      name: "keys",
      type_name: "ObjectKey",
      list: true,
      value: ObjectValue.new([
        Argument.new(
          name: "slug",
          type_name: "String",
          value: KeyValue.new(["slug"]),
        ),
        Argument.new(
          name: "nestedList",
          type_name: "ObjectKey",
          list: true,
          value: ObjectValue.new([
            Argument.new(
              name: "slug",
              type_name: "String",
              value: KeyValue.new(["ref", "slug"]),
            ),
          ]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Arguments.parse(template, arg_defs("objectListKey"))
  end

  def test_builds_objects_into_custom_scalar_with_no_typing
    template = "key: {slug: $.slug, nested: {slug: $.slug}}"
    expected = [Argument.new(
      name: "key",
      type_name: "ScalarKey",
      list: false,
      value: ObjectValue.new([
        Argument.new(
          name: "slug",
          type_name: nil,
          value: KeyValue.new(["slug"]),
        ),
        Argument.new(
          name: "nested",
          type_name: nil,
          value: ObjectValue.new([
            Argument.new(
              name: "slug",
              type_name: nil,
              value: KeyValue.new(["slug"]),
            ),
          ]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Arguments.parse(template, arg_defs("scalarKey"))
  end

  def test_errors_for_building_objects_into_builtin_scalars
    assert_error "can only be built into custom scalar types" do
      template = "key: {slug: $.slug, namespace: $.namespace}"
      GraphQL::Stitching::Arguments.parse(template, arg_defs("builtinScalarKey"))
    end
  end

  def test_errors_for_building_objects_into_non_object_non_scalars
    assert_error "can only be built into input object and scalar positions" do
      template = "key: {slug: $.slug, namespace: $.namespace}"
      GraphQL::Stitching::Arguments.parse(template, arg_defs("enumKey"))
    end
  end

  def test_errors_building_invalid_root_keys
    assert_error "`invalid` is not a valid argument" do
      template = "key: {slug: $.slug, namespace: $.namespace}, invalid: true"
      GraphQL::Stitching::Arguments.parse(template, arg_defs("objectKey"))
    end
  end

  def test_errors_building_invalid_object_keys
    assert_error "`invalid` is not a valid argument" do
      template = "key: {slug: $.slug, namespace: $.namespace, invalid: true}"
      GraphQL::Stitching::Arguments.parse(template, arg_defs("objectKey"))
    end
  end

  def test_errors_omitting_a_required_root_argument
    assert_error "Required argument `key` has no input" do
      GraphQL::Stitching::Arguments.parse(%|other:"test"|, arg_defs("objectKey"))
    end
  end

  def test_errors_omitting_a_required_object_argument
    assert_error "Required argument `slug` has no input" do
      GraphQL::Stitching::Arguments.parse(%|key: {namespace: $.namespace}|, arg_defs("objectKey"))
    end
  end

  private

  def arg_defs(field_name)
    TestSchema.query.get_field(field_name).arguments
  end
end
