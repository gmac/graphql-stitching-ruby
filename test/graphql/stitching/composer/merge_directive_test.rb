# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging directives' do

  def test_merges_directives
    a = <<~GRAPHQL
      """a"""
      directive @fizz(a: String!) on OBJECT
      directive @bang on OBJECT
      type Test @fizz(a: "A") { field: String }
      type Query { test: Test }
    GRAPHQL

    b = <<~GRAPHQL
      """b"""
      directive @fizz(a: String!, b: String) on OBJECT
      directive @widget on OBJECT
      type Test @fizz(a: "A", b: "B") { field: String }
      type Query { test: Test }
    GRAPHQL

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    puts supergraph.schema.to_definition
    # assert_equal "a/b", info.schema.types["Test"].description
  end
end
