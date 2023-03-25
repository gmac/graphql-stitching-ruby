# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"
require_relative "../../../schemas/introspection"

describe 'GraphQL::Stitching, introspection' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Example::Products,
      "storefronts" => Schemas::Example::Storefronts,
      "manufacturers" => Schemas::Example::Manufacturers,
    })
  end

  def test_performs_full_introspection
    result = plan_and_execute(@supergraph, INTROSPECTION_QUERY)

    introspection_types = result.dig("data", "__schema", "types").map { _1["name"] }
    expected_types = ["Manufacturer", "Product", "Query", "Storefront"]
    expected_types += ["Boolean", "Float", "ID", "Int", "String"]
    expected_types += GraphQL::Stitching::Supergraph::INTROSPECTION_TYPES
    assert_equal expected_types.sort, introspection_types.sort
  end

  def test_performs_schema_introspection_with_other_stitching
    result = plan_and_execute(@supergraph, %|
      {
        __schema {
          queryType { name }
        }
        product(upc: "1") {
          name
          manufacturer { name }
        }
      }
    |)

    expected = {
      "data" => {
        "__schema" => {
          "queryType" => {
            "name" => "Query",
          },
        },
        "product" => {
          "name" => "iPhone",
          "manufacturer" => {
            "name" => "Apple",
          },
        },
      },
    }

    assert_equal expected, result
  end

  def test_performs_type_introspection_with_other_stitching
    result = plan_and_execute(@supergraph, %|
      {
        __type(name: "Product") {
          name
          kind
        }
        product(upc: "1") {
          name
          manufacturer { name }
        }
      }
    |)

    expected = {
      "data" => {
        "__type" => {
          "name" => "Product",
          "kind" => "OBJECT",
        },
        "product" => {
          "name" => "iPhone",
          "manufacturer" => {
            "name" => "Apple",
          },
        },
      },
    }

    assert_equal expected, result
  end

  def test_handles_introspection_type_inline_fragments
    result = plan_and_execute(@supergraph, %|
      {
        __typename
        ...on __Directive { __typename }
        ...on __EnumValue { __typename }
        ...on __InputValue { __typename }
        ...on __Field { __typename }
        ...on __Schema { __typename }
        ...on __Type { __typename }
        product(upc: "1") {
          ...on __Directive { __typename }
          ...on __EnumValue { __typename }
          ...on __InputValue { __typename }
          ...on __Field { __typename }
          ...on __Schema { __typename }
          ...on __Type { __typename }
        }
      }
    |)

    expected = { "data" => { "__typename" => "Query", "product" => {} } }
    assert_equal expected, result
  end

  def test_handles_introspection_type_fragment_spreads
    result = plan_and_execute(@supergraph, %|
      fragment DirectiveAttrs on __Directive { __typename }
      fragment EnumValueAttrs on __EnumValue { __typename }
      fragment InputValueAttrs on __InputValue { __typename }
      fragment FieldAttrs on __Field { __typename }
      fragment SchemaAttrs on __Schema { __typename }
      fragment TypeAttrs on __Type { __typename }
      {
        __typename
        ...DirectiveAttrs
        ...EnumValueAttrs
        ...InputValueAttrs
        ...FieldAttrs
        ...SchemaAttrs
        ...TypeAttrs
        product(upc: "1") {
          ...DirectiveAttrs
          ...EnumValueAttrs
          ...InputValueAttrs
          ...FieldAttrs
          ...SchemaAttrs
          ...TypeAttrs
        }
      }
    |)

    expected = { "data" => { "__typename" => "Query", "product" => {} } }
    assert_equal expected, result
  end
end
