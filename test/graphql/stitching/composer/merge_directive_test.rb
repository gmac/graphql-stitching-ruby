# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging directives' do

  def test_merges_directive_definitions
    a = <<~GRAPHQL
      """a"""
      directive @fizzbuzz(a: String!) on OBJECT
      type Test @fizzbuzz(a: "A") { field: String }
      type Query { test: Test }
    GRAPHQL

    b = <<~GRAPHQL
      """b"""
      directive @fizzbuzz(a: String!, b: String) on OBJECT
      type Test @fizzbuzz(a: "A", b: "B") { field: String }
      type Query { test: Test }
    GRAPHQL

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    directive_definition = supergraph.schema.directives["fizzbuzz"]
    assert_equal "a/b", directive_definition.description
    assert_equal ["a"], directive_definition.arguments.keys
  end

  def test_combines_distinct_directives_assigned_to_an_element
    a = <<~GRAPHQL
      directive @fizz(arg: String!) on OBJECT
      directive @buzz on OBJECT
      type Test @fizz(arg: "a") @buzz { field: String }
      type Query { test:Test }
    GRAPHQL

    b = <<~GRAPHQL
      directive @fizz(arg: String!) on OBJECT
      directive @widget on OBJECT
      type Test @fizz(arg: "b") @widget { field: String }
      type Query { test:Test }
    GRAPHQL

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    directives = supergraph.schema.types["Test"].directives

    assert_equal 3, directives.length
    assert_equal ["buzz", "fizz", "widget"], directives.map(&:graphql_name).sort
    assert_equal "a/b", directives.find { _1.graphql_name == "fizz" }.arguments.keyword_arguments[:arg]
  end

  def test_omits_stitching_directives
    a = <<~GRAPHQL
      directive @stitch(key: String!) repeatable on FIELD_DEFINITION
      type Test { id: ID! a: String }
      type Query { testA(id: ID!): Test @stitch(key: "id") }
    GRAPHQL

    b = <<~GRAPHQL
      directive @stitch(key: String!) repeatable on FIELD_DEFINITION
      type Test { id: ID! b: String }
      type Query { testB(id: ID!): Test @stitch(key: "id") }
    GRAPHQL

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_nil supergraph.schema.directives["stitch"]
    assert_equal 0, supergraph.schema.types["Query"].fields["testA"].directives.length
    assert_equal 0, supergraph.schema.types["Query"].fields["testB"].directives.length
  end
end
