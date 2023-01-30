# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging unions' do

  def test_merges_union_types
    a = %{type A { a:Int } union Thing = A type Query { thing:Thing }}
    b = %{type B { b:Int } type C { b:Int } union Thing = B | C type Query { thing:Thing }}

    info = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["A", "B", "C"], info.schema.types["Thing"].possible_types.map(&:graphql_name).sort
  end

  def test_merges_union_descriptions
    a = %{type A { a:Int } """a""" union Thing = A type Query { thing:Thing }}
    b = %{type B { b:Int } """b""" union Thing = B type Query { thing:Thing }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.types["Thing"].description
  end
end
