# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::TypeResolver::KeysTest < Minitest::Test
  Key = GraphQL::Stitching::TypeResolver::Key
  KeyFieldSet = GraphQL::Stitching::TypeResolver::KeyFieldSet
  KeyField = GraphQL::Stitching::TypeResolver::KeyField
  FieldNode = GraphQL::Stitching::TypeResolver::FieldNode

  def test_formats_export_keys
    assert_equal "_export_id", GraphQL::Stitching::TypeResolver.export_key("id")
  end

  def test_identifies_export_keys
    assert GraphQL::Stitching::TypeResolver.export_key?("_export_id")
    assert !GraphQL::Stitching::TypeResolver.export_key?("id")
  end

  def test_parses_key_with_locations
    key = GraphQL::Stitching::TypeResolver.parse_key("id reference { id __typename }", ["a", "b"])
    expected = Key.new([
      KeyField.new("id"),
      KeyField.new(
        "reference",
        inner: KeyFieldSet.new([
          KeyField.new("id"),
          KeyField.new("__typename"),
        ]),
      ),
    ])
    assert_equal expected, key
    assert_equal ["a", "b"], key.locations
  end

  def test_fulfills_key_set_uniqueness
    keys = [
      GraphQL::Stitching::TypeResolver.parse_key("id"),
      GraphQL::Stitching::TypeResolver.parse_key("id"),
      GraphQL::Stitching::TypeResolver.parse_key("sku id"),
      GraphQL::Stitching::TypeResolver.parse_key("id sku"),
      GraphQL::Stitching::TypeResolver.parse_key("ref { a b } c"),
      GraphQL::Stitching::TypeResolver.parse_key("c ref { b a }"),
    ].uniq(&:to_definition)

    assert_equal ["id", "id sku", "c ref { a b }"], keys.map(&:to_definition)
  end

  def test_matches_basic_keys
    key1 = GraphQL::Stitching::TypeResolver.parse_key("id")
    key2 = GraphQL::Stitching::TypeResolver.parse_key("id")
    key3 = GraphQL::Stitching::TypeResolver.parse_key("sku")
    assert key1 == key2
    assert key2 == key1
    assert key1 != key3
    assert key3 != key1
  end

  def test_matches_key_sets
    key1 = GraphQL::Stitching::TypeResolver.parse_key("id sku")
    key2 = GraphQL::Stitching::TypeResolver.parse_key("sku id")
    key3 = GraphQL::Stitching::TypeResolver.parse_key("id upc")
    key4 = GraphQL::Stitching::TypeResolver.parse_key("id")
    assert key1 == key2
    assert key2 == key1
    assert key1 != key3
    assert key1 != key4
  end

  def test_matches_nested_key_sets
    key1 = GraphQL::Stitching::TypeResolver.parse_key("id ref { ns key }")
    key2 = GraphQL::Stitching::TypeResolver.parse_key("ref { key ns } id")
    key3 = GraphQL::Stitching::TypeResolver.parse_key("id ref { key }")
    key4 = GraphQL::Stitching::TypeResolver.parse_key("ref { key ns }")
    assert key1 == key2
    assert key2 == key1
    assert key1 != key3
    assert key1 != key4
  end

  def test_matches_nested_and_unnested_key_names_dont_match
    key1 = GraphQL::Stitching::TypeResolver.parse_key("ref { key }")
    key2 = GraphQL::Stitching::TypeResolver.parse_key("ref")
    assert key1 != key2
    assert key2 != key1
  end

  def test_prints_a_basic_key
    key1 = GraphQL::Stitching::TypeResolver.parse_key("id")
    key2 = GraphQL::Stitching::TypeResolver.parse_key("ref id")
    key3 = GraphQL::Stitching::TypeResolver.parse_key("ref { ns key } id")

    assert_equal "id", key1.to_definition
    assert_equal "id ref", key2.to_definition
    assert_equal "id ref { key ns }", key3.to_definition
  end

  def test_errors_for_non_field_keys
    assert_error("selections must be fields") do
      GraphQL::Stitching::TypeResolver.parse_key("...{ id }")
    end
  end

  def test_errors_for_aliased_keys
    assert_error("may not specify aliases") do
      GraphQL::Stitching::TypeResolver.parse_key("id: key")
    end
  end

  def test_formats_flat_export_nodes
    key = GraphQL::Stitching::TypeResolver.parse_key("id")
    expected = [
      FieldNode.build(
        field_alias: "_export_id",
        field_name: "id",
        selections: [],
      ),
      FieldNode.build(
        field_alias: "_export___typename",
        field_name: "__typename",
        selections: [],
      ),
    ]

    assert_equal expected, key.export_nodes
  end

  def test_formats_nested_export_nodes
    key = GraphQL::Stitching::TypeResolver.parse_key("ref { key } id")
    expected = [
      FieldNode.build(
        field_alias: "_export_id",
        field_name: "id",
        selections: [],
      ),
      FieldNode.build(
        field_alias: "_export_ref",
        field_name: "ref",
        selections: [
          FieldNode.build(
            field_alias: nil,
            field_name: "key",
            selections: [],
          ),
        ],
      ),
      FieldNode.build(
        field_alias: "_export___typename",
        field_name: "__typename",
        selections: [],
      ),
    ]

    assert_equal expected, key.export_nodes
  end

  def test_builds_keys_with_type_mapping
    a = %|
      type Test { id: ID! test: Test list: [Test] }
      type Query { test(id: ID): Test @stitch(key: "id") }
    |
    b = %|
      type Test { id: ID! }
      type Query { test(id: ID): Test @stitch(key: "id") }
    |

    compose_definitions({ a: a, b: b }) do |composer|
      field = GraphQL::Stitching::TypeResolver.parse_key_with_types(
        "test { id list { id } }",
        composer.subgraph_types_by_name_and_location["Test"],
      ).first

      assert_equal "Test", field.type_name
      assert_equal false, field.list?

      id_field = field.inner[0]
      assert_equal "ID", id_field.type_name
      assert_equal false, id_field.list?

      list_field = field.inner[1]
      assert_equal "Test", list_field.type_name
      assert_equal true, list_field.list?
    end
  end

  def test_composite_keys_must_contain_inner_selections
    a = %|
      type Test { id: ID! test: Test }
      type Query { test(id: ID): Test @stitch(key: "id") }
    |
    b = %|
      type Test { id: ID! }
      type Query { test(id: ID): Test @stitch(key: "id") }
    |

    compose_definitions({ a: a, b: b }) do |composer|
      assert_error("Composite key fields must contain nested selections") do
        GraphQL::Stitching::TypeResolver.parse_key_with_types(
          "test",
          composer.subgraph_types_by_name_and_location["Test"],
        )
      end
    end
  end

  def test_keys_must_be_fully_available_in_at_least_one_location
    a = %|
      type Test { id: ID! a: String! test: Test }
      type Query { testA(id: ID!): Test @stitch(key: "id") }
    |
    b = %|
      type Test { id: ID! sku: ID! }
      type Query { testB(id: ID, sku: ID): Test @stitch(key: "id") @stitch(key: "sku") }
    |
    c = %|
      type Test { sku: ID! b: String! test: Test }
      type Query { testC(sku: ID!): Test @stitch(key: "sku") }
    |

    compose_definitions({ a: a, b: b, c: c }) do |composer|
      ["id", "sku", "id sku", "id test { a }", "sku test { b }"].each do |key|
        assert GraphQL::Stitching::TypeResolver.parse_key_with_types(key, composer.subgraph_types_by_name_and_location["Test"])
      end

      ["id test { b }", "sku test { a }", "test { a b }"].each do |key|
        assert_error("Key `#{key}` does not exist in any location") do
          GraphQL::Stitching::TypeResolver.parse_key_with_types(key, composer.subgraph_types_by_name_and_location["Test"])
        end
      end
    end
  end

  def test_keys_assign_locations
    a = %|
      type Test { id: ID! a: String! test: Test }
      type Query { testA(id: ID!): Test @stitch(key: "id") }
    |
    b = %|
      type Test { id: ID! sku: ID! }
      type Query { testB(id: ID, sku: ID): Test @stitch(key: "id") @stitch(key: "sku") }
    |
    c = %|
      type Test { sku: ID! b: String! test: Test }
      type Query { testC(sku: ID!): Test @stitch(key: "sku") }
    |

    compose_definitions({ a: a, b: b, c: c }) do |composer|
      k1 = GraphQL::Stitching::TypeResolver.parse_key_with_types("id", composer.subgraph_types_by_name_and_location["Test"])
      assert_equal ["a", "b"], k1.locations

      k2 = GraphQL::Stitching::TypeResolver.parse_key_with_types("sku", composer.subgraph_types_by_name_and_location["Test"])
      assert_equal ["b", "c"], k2.locations

      k3 = GraphQL::Stitching::TypeResolver.parse_key_with_types("id test { a }", composer.subgraph_types_by_name_and_location["Test"])
      assert_equal ["a"], k3.locations

      k4 = GraphQL::Stitching::TypeResolver.parse_key_with_types("id sku", composer.subgraph_types_by_name_and_location["Test"])
      assert_equal ["b"], k4.locations

      k5 = GraphQL::Stitching::TypeResolver.parse_key_with_types("sku test { b }", composer.subgraph_types_by_name_and_location["Test"])
      assert_equal ["c"], k5.locations
    end
  end
end
