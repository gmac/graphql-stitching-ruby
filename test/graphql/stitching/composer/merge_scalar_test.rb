# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging scalars' do

  def test_merges_scalar_descriptions
    a = %{"""a""" scalar URL type Query { url:URL }}
    b = %{"""b""" scalar URL type Query { url:URL }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.get_type("URL").description
  end

  def test_merges_scalar_directives
    a = <<~GRAPHQL
      directive @fizzbuzz(arg: String!) on SCALAR
      scalar Thing @fizzbuzz(arg: "a")
      type Query { thing:Thing }
    GRAPHQL

    b = <<~GRAPHQL
      directive @fizzbuzz(arg: String!) on SCALAR
      scalar Thing @fizzbuzz(arg: "b")
      type Query { thing:Thing }
    GRAPHQL

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.get_type("Thing").directives.first.arguments.keyword_arguments[:arg]
  end
end
