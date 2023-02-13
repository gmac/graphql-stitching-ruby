# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Document" do

  def test_builds_with_pre_parsed_ast
    ast = GraphQL.parse("query First { widget { id } }")
    document = GraphQL::Stitching::Document.new(ast)

    assert_equal "query", document.operation.operation_type
    assert_equal "widget", document.operation.selections.first.name
  end

  def test_selects_single_operation_by_default
    document = GraphQL::Stitching::Document.new("query First { widget { id } }")

    assert_equal "query", document.operation.operation_type
    assert_equal "widget", document.operation.selections.first.name
  end

  def test_selects_from_multiple_operations_by_operation_name
    query = "
      query First { widget { id } }
      query Second { sprocket { id } }
      mutation Third { makeSprocket(id: \"1\") { id } }
    "
    document1 = GraphQL::Stitching::Document.new(query, operation_name: "First")
    document2 = GraphQL::Stitching::Document.new(query, operation_name: "Second")
    document3 = GraphQL::Stitching::Document.new(query, operation_name: "Third")

    assert_equal "query", document1.operation.operation_type
    assert_equal "query", document2.operation.operation_type
    assert_equal "mutation", document3.operation.operation_type

    assert_equal "widget", document1.operation.selections.first.name
    assert_equal "sprocket", document2.operation.selections.first.name
  end

  def test_errors_for_multiple_operations_given_without_operation_name
    query = "query First { widget { id } } query Second { sprocket { id } }"

    assert_error "An operation name is required", GraphQL::ExecutionError do
      GraphQL::Stitching::Document.new(query)
    end
  end

  def test_errors_for_invalid_operation_names
    query = "query First { widget { id } } query Second { sprocket { id } }"

    assert_error "Invalid root operation", GraphQL::ExecutionError do
      GraphQL::Stitching::Document.new(query, operation_name: "Invalid")
    end
  end

  def test_errors_for_invalid_operation_types
    assert_error "Invalid root operation", GraphQL::ExecutionError do
      GraphQL::Stitching::Document.new("subscription { movie }")
    end
  end

  def test_accesses_document_variable_definitions
    query = "
      query($ids: [ID!]!, $ns: String!, $lang: String) {
        widget(ids: $ids, ns: $ns) { id name(lang: $lang) }
      }
    "
    document = GraphQL::Stitching::Document.new(query)
    variables = document.variable_definitions.each_with_object({}) do |(name, type), memo|
      memo[name] = GraphQL::Language::Printer.new.print(type)
    end

    expected = {
      "ids" => "[ID!]!",
      "ns" => "String!",
      "lang" => "String",
    }

    assert_equal expected, variables
  end

  def test_accesses_document_fragment_definitions
    query = "
      query { things { ...WidgetAttrs ...SprocketAttrs } }
      fragment WidgetAttrs on Widget { widget }
      fragment SprocketAttrs on Sprocket { sprocket }
    "
    document = GraphQL::Stitching::Document.new(query)

    assert_equal "widget", document.fragment_definitions["WidgetAttrs"].selections.first.name
    assert_equal "sprocket", document.fragment_definitions["SprocketAttrs"].selections.first.name
  end

  def test_generates_a_digest_from_string_and_ast_input
    sample_ast = GraphQL.parse("query { things { name } }")
    sample_query = GraphQL::Language::Printer.new.print(sample_ast)
    expected_digest = "88908d0790f7b20afe4a7508a8bba6343c62f98abb9c5abff17345c64d90c0d0"

    document1 = GraphQL::Stitching::Document.new(sample_ast)
    assert_equal expected_digest, document1.digest

    document2 = GraphQL::Stitching::Document.new(sample_query)
    assert_equal expected_digest, document2.digest
  end

  def test_prepare_variables_collects_variable_defaults
    query = <<~GRAPHQL
      query($a: String! = "defaultA", $b: String! = "defaultB") {
        base(a: $a, b: $b) { id }
      }
    GRAPHQL

    document = GraphQL::Stitching::Document.new(GraphQL.parse(query), variables: { "a" => "yes" })
    expected = { "a" => "yes", "b" => "defaultB" }
    document.prepare!
    assert_equal expected, document.variables
  end

  def test_applies_skip_and_include_directives_via_boolean_literals
    query = <<~GRAPHQL
      query {
        skipKeep @skip(if: false) { id }
        skipOmit @skip(if: true) { id }
        includeKeep @include(if: true) { id }
        includeOmit @include(if: false) { id }
      }
    GRAPHQL

    document = GraphQL::Stitching::Document.new(GraphQL.parse(query))
    document.prepare!

    assert_equal "query { skipKeep { id } includeKeep { id } }", squish_string(document.ast.to_query_string)
  end

  def test_applies_skip_and_include_directives_via_variables
    query = <<~GRAPHQL
      query($yes: Boolean!, $no: Boolean!) {
        skipKeep @skip(if: $no) { id }
        skipOmit @skip(if: $yes) { id }
        includeKeep @include(if: $yes) { id }
        includeOmit @include(if: $no) { id }
      }
    GRAPHQL

    document = GraphQL::Stitching::Document.new(GraphQL.parse(query), variables: { "yes" => true, "no" => false })
    document.prepare!

    expected = "query($yes: Boolean!, $no: Boolean!) { skipKeep { id } includeKeep { id } }"
    assert_equal expected, squish_string(document.ast.to_query_string)
  end
end
