# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging interfaces' do

  def test_merges_interface_descriptions
    a = %{"""a""" interface Test { field: String } type Query { test:Test }}
    b = %{"""b""" interface Test { field: String } type Query { test:Test }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.types["Test"].description
  end

  def test_merges_interface_directives
    a = <<~GRAPHQL
      directive @fizzbuzz(arg: String!) on INTERFACE
      interface Test @fizzbuzz(arg: "a") { field: String }
      type Query { test:Test }
    GRAPHQL

    b = <<~GRAPHQL
      directive @fizzbuzz(arg: String!) on INTERFACE
      interface Test @fizzbuzz(arg: "b") { field: String }
      type Query { test:Test }
    GRAPHQL

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _supergraph) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.types["Test"].directives.first.arguments.keyword_arguments[:arg]
  end

  def test_merges_interface_memberships
    a = %{interface A { id:ID } interface AA implements A { id:ID } type C implements AA { id:ID } type Query { c:C }}
    b = %{interface B { id:ID } interface BB implements B { id:ID } type C implements BB { id:ID } type Query { c:C }}

    info = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["A"], info.schema.types["AA"].interfaces.map(&:graphql_name).sort
    assert_equal ["B"], info.schema.types["BB"].interfaces.map(&:graphql_name).sort
    assert_equal ["A", "AA", "B", "BB"], info.schema.types["C"].interfaces.map(&:graphql_name).sort
  end

  def test_merges_interface_fields
    a = %{
      interface I { id:ID! name:String }
      type T implements I { id:ID! name:String }
      type Query { t(id:ID!):T @stitch(key: "id") }
    }
    b = %{
      interface I { id:ID! code:String }
      type T implements I { id:ID! code:String }
      type Query { t(id:ID!):T @stitch(key: "id") }
    }

    info = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["code", "id", "name"], info.schema.types["I"].fields.keys.sort
    assert_equal ["code", "id", "name"], info.schema.types["T"].fields.keys.sort
  end

  # def test_validates_merged_interface_fields_match_implementation_fields
  #   # is this really a problem...? Implementing objects have to have matching fields across services.
  #   # possibly applies to nullability concerns.
  # end
end
