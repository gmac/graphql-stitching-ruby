# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging unions' do

  def test_merges_union_types
    a = %{type A { a:Int } union Thing = A type Query { thing:Thing }}
    b = %{type B { b:Int } type C { b:Int } union Thing = B | C type Query { thing:Thing }}

    info = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["A", "B", "C"], info.schema.get_type("Thing").possible_types.map(&:graphql_name).sort
  end

  def test_merges_union_descriptions
    a = %{type A { a:Int } """a""" union Thing = A type Query { thing:Thing }}
    b = %{type B { b:Int } """b""" union Thing = B type Query { thing:Thing }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.get_type("Thing").description
  end

  def test_merges_union_directives
    a = <<~GRAPHQL
      directive @fizzbuzz(arg: String!) on UNION
      type A { a:Int }
      union Thing @fizzbuzz(arg: "a") = A
      type Query { thing:Thing }
    GRAPHQL

    b = <<~GRAPHQL
      directive @fizzbuzz(arg: String!) on UNION
      type B { b:Int }
      union Thing @fizzbuzz(arg: "b") = B
      type Query { thing:Thing }
    GRAPHQL

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.get_type("Thing").directives.first.arguments.keyword_arguments[:arg]
  end
end
