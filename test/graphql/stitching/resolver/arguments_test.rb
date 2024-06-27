# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::Resolver::ArgumentsTest < Minitest::Test
  Argument = GraphQL::Stitching::Resolver::Argument
  ObjectArgumentValue = GraphQL::Stitching::Resolver::ObjectArgumentValue
  ArgumentLiteralValue = GraphQL::Stitching::Resolver::ArgumentLiteralValue
  ArgumentEnumValue = GraphQL::Stitching::Resolver::ArgumentEnumValue
  KeyArgumentValue = GraphQL::Stitching::Resolver::KeyArgumentValue

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
        f.argument(:other, String, required: false)
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

      field :basic_key, Boolean, null: false do |f|
        f.argument(:key, ID, required: true)
        f.argument(:scope, String, required: false)
        f.argument(:mode, TestEnum, required: false)
      end
    end

    query Query
  end

  def test_builds_flat_object_key_into_matching_input_object
    template = "key: {slug: $.slug, namespace: 'sfoo'}, other: $.slug"
    expected = [Argument.new(
      name: "key",
      type_name: "ObjectKey",
      list: false,
      value: ObjectArgumentValue.new([
        Argument.new(
          name: "slug",
          type_name: "String",
          value: KeyArgumentValue.new(["slug"]),
        ),
        Argument.new(
          name: "namespace",
          type_name: "String",
          value: ArgumentLiteralValue.new("sfoo"),
        ),
      ]),
    ),
    Argument.new(
      name: "other",
      type_name: "String",
      value: KeyArgumentValue.new(["slug"]),
    )]

    assert_equal expected, GraphQL::Stitching::Resolver.parse_arguments(template, get_field("objectKey"))
  end

  def test_builds_nested_object_key_into_matching_input_objects
    template = "key: {slug: $.slug, nested:{slug: $.slug, namespace: 'sfoo'}}"
    expected = [Argument.new(
      name: "key",
      type_name: "ObjectKey",
      list: false,
      value: ObjectArgumentValue.new([
        Argument.new(
          name: "slug",
          type_name: "String",
          value: KeyArgumentValue.new(["slug"]),
        ),
        Argument.new(
          name: "nested",
          type_name: "ObjectKey",
          value: ObjectArgumentValue.new([
            Argument.new(
              name: "slug",
              type_name: "String",
              value: KeyArgumentValue.new(["slug"]),
            ),
            Argument.new(
              name: "namespace",
              type_name: "String",
              value: ArgumentLiteralValue.new("sfoo"),
            ),
          ]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Resolver.parse_arguments(template, get_field("objectKey"))
  end

  def test_builds_nested_key_paths
    template = "key: {slug: $.ref.slug}"
    expected = [Argument.new(
      name: "key",
      type_name: "ObjectKey",
      list: false,
      value: ObjectArgumentValue.new([
        Argument.new(
          name: "slug",
          type_name: "String",
          value: KeyArgumentValue.new(["ref", "slug"]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Resolver.parse_arguments(template, get_field("objectKey"))
  end

  def test_builds_object_list_keys_into_matching_inputs
    template = "keys: {slug: $.slug, nestedList: {slug: $.ref.slug}}"
    expected = [Argument.new(
      name: "keys",
      type_name: "ObjectKey",
      list: true,
      value: ObjectArgumentValue.new([
        Argument.new(
          name: "slug",
          type_name: "String",
          value: KeyArgumentValue.new(["slug"]),
        ),
        Argument.new(
          name: "nestedList",
          type_name: "ObjectKey",
          list: true,
          value: ObjectArgumentValue.new([
            Argument.new(
              name: "slug",
              type_name: "String",
              value: KeyArgumentValue.new(["ref", "slug"]),
            ),
          ]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Resolver.parse_arguments(template, get_field("objectListKey"))
  end

  def test_builds_objects_into_custom_scalar_with_no_typing
    template = "key: {slug: $.slug, nested: {slug: $.slug}}"
    expected = [Argument.new(
      name: "key",
      type_name: "ScalarKey",
      list: false,
      value: ObjectArgumentValue.new([
        Argument.new(
          name: "slug",
          type_name: nil,
          value: KeyArgumentValue.new(["slug"]),
        ),
        Argument.new(
          name: "nested",
          type_name: nil,
          value: ObjectArgumentValue.new([
            Argument.new(
              name: "slug",
              type_name: nil,
              value: KeyArgumentValue.new(["slug"]),
            ),
          ]),
        ),
      ]),
    )]

    assert_equal expected, GraphQL::Stitching::Resolver.parse_arguments(template, get_field("scalarKey"))
  end

  def test_errors_for_building_objects_into_builtin_scalars
    assert_error "can only be built into custom scalar types" do
      template = "key: {slug: $.slug, namespace: $.namespace}"
      GraphQL::Stitching::Resolver.parse_arguments(template, get_field("builtinScalarKey"))
    end
  end

  def test_errors_for_building_objects_into_non_object_non_scalars
    assert_error "can only be built into input object and scalar positions" do
      template = "key: {slug: $.slug, namespace: $.namespace}"
      GraphQL::Stitching::Resolver.parse_arguments(template, get_field("enumKey"))
    end
  end

  def test_errors_building_invalid_root_keys
    assert_error "`invalid` is not a valid argument" do
      template = "key: {slug: $.slug, namespace: $.namespace}, invalid: true"
      GraphQL::Stitching::Resolver.parse_arguments(template, get_field("objectKey"))
    end
  end

  def test_errors_building_invalid_object_keys
    assert_error "`invalid` is not a valid argument" do
      template = "key: {slug: $.slug, namespace: $.namespace, invalid: true}"
      GraphQL::Stitching::Resolver.parse_arguments(template, get_field("objectKey"))
    end
  end

  def test_errors_omitting_a_required_root_argument
    assert_error "Required argument `key` has no input" do
      GraphQL::Stitching::Resolver.parse_arguments(%|other:"test"|, get_field("objectKey"))
    end
  end

  def test_errors_omitting_a_required_object_argument
    assert_error "Required argument `slug` has no input" do
      GraphQL::Stitching::Resolver.parse_arguments(%|key: {namespace: $.namespace}|, get_field("objectKey"))
    end
  end

  def test_errors_building_keys_into_non_list_arguments_for_list_fields
    assert_error "Cannot use repeatable key `$.slug` in non-list argument `other`" do
      GraphQL::Stitching::Resolver.parse_arguments(%|keys: {slug: $.slug} other: $.slug|, get_field("objectListKey"))
    end
  end

  def test_arguments_build_expected_value_structure
    template = "key: {slug: $.name, namespace: 'sol', nested:{slug: $.outer.name, namespace: $.outer.galaxy}}"
    arg = GraphQL::Stitching::Resolver.parse_arguments(template, get_field("objectKey")).first

    origin_obj = {
      "_export_name" => "neptune",
      "_export_outer" => {
        "_export_name" => "saturn",
        "_export_galaxy" => "milkyway",
      }
    }

    expected = {
      "slug" => "neptune",
      "namespace" => "sol",
      "nested" => {
        "slug" => "saturn",
        "namespace" => "milkyway",
      }
    }

    assert_equal expected, arg.build(origin_obj)
  end

  def test_arguments_build_primitive_keys
    template = "key: $.key, scope: 'foo', mode: YES"
    args = GraphQL::Stitching::Resolver.parse_arguments(template, get_field("basicKey"))
    origin_obj = { "_export_key" => "123" }

    assert_equal ["123", "foo", "YES"], args.map { _1.build(origin_obj) }
  end

  def test_arguments_allows_wrapping_parenthesis
    template = "(key: $.key)"
    args = GraphQL::Stitching::Resolver.parse_arguments(template, get_field("basicKey"))
    origin_obj = { "_export_key" => "123" }

    assert_equal ["123"], args.map { _1.build(origin_obj) }
  end

  def test_prints_argument_object_structures
    template = "key: {slug: $.name, namespace: 'sol', nested: {slug: $.outer.name, namespace: $.outer.galaxy}}"
    arg = GraphQL::Stitching::Resolver.parse_arguments(template, get_field("objectKey")).first

    assert_equal template, arg.to_definition
    assert_equal template.gsub("'", %|"|), arg.print
    assert_equal "key: ObjectKey!", arg.to_type_definition
  end

  def test_prints_primitive_argument_types
    template = "key: $.key, scope: 'foo', mode: YES"
    args = GraphQL::Stitching::Resolver.parse_arguments(template, get_field("basicKey"))

    assert_equal template, args.map(&:to_definition).join(", ")
    assert_equal template.gsub("'", %|"|), args.map(&:print).join(", ")
    assert_equal "key: ID!, scope: String!, mode: TestEnum!", args.map(&:to_type_definition).join(", ")
  end

  def test_parse_arguments_with_type_defs
    template = "keys: {slug: $.name, namespace: 'beep'}, other: 'boom'"
    type_defs = "keys: [ObjectKey], other: String"
    expected = [Argument.new(
      name: "keys",
      type_name: "ObjectKey",
      list: true,
      value: ObjectArgumentValue.new([
        Argument.new(
          name: "slug",
          value: KeyArgumentValue.new(["name"]),
        ),
        Argument.new(
          name: "namespace",
          value: ArgumentLiteralValue.new("beep"),
        ),
      ]),
    ),
    Argument.new(
      name: "other",
      type_name: "String",
      value: ArgumentLiteralValue.new("boom"),
    )]

    assert_equal expected, GraphQL::Stitching::Resolver.parse_arguments_with_type_defs(template, type_defs)
  end

  def test_checks_primitive_values_for_presence_of_keys
    assert_equal false, Argument.new(name: "test", value: ArgumentLiteralValue.new("boom")).key?
    assert_equal false, Argument.new(name: "test", value: ArgumentEnumValue.new("YES")).key?
    assert Argument.new(name: "test", value: KeyArgumentValue.new("id")).key?
  end

  def test_checks_composite_values_for_presence_of_keys
    assert_equal false, Argument.new(
      name: "test",
      value: ObjectArgumentValue.new([
        Argument.new(
          name: "first",
          value: ArgumentEnumValue.new(["YES"]),
        ),
        Argument.new(
          name: "second",
          value: ArgumentLiteralValue.new("boom"),
        ),
      ]),
    ).key?

    assert Argument.new(
      name: "test",
      value: ObjectArgumentValue.new([
        Argument.new(
          name: "first",
          value: ArgumentEnumValue.new(["YES"]),
        ),
        Argument.new(
          name: "second",
          value: ArgumentLiteralValue.new("boom"),
        ),
        Argument.new(
          name: "third",
          value: KeyArgumentValue.new("id"),
        ),
      ]),
    ).key?
  end

  private

  def get_field(field_name)
    TestSchema.query.get_field(field_name)
  end
end
