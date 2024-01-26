# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging interfaces' do

  def test_merges_interface_descriptions
    a = %{"""a""" interface Test { field: String } type Query { test:Test }}
    b = %{"""b""" interface Test { field: String } type Query { test:Test }}

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.types["Test"].description
  end

  def test_merges_interface_directives
    a = %|
      directive @fizzbuzz(arg: String!) on INTERFACE
      interface Test @fizzbuzz(arg: "a") { field: String }
      type Query { test:Test }
    |

    b = %|
      directive @fizzbuzz(arg: String!) on INTERFACE
      interface Test @fizzbuzz(arg: "b") { field: String }
      type Query { test:Test }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.types["Test"].directives.first.arguments.keyword_arguments[:arg]
  end

  def test_merges_single_interface_memberships
    a = %{interface A { id:ID } type C implements A { id:ID } type Query { c:C }}
    b = %{interface B { id:ID } type C implements B { id:ID } type Query { c:C }}

    supergraph = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["A", "B"], supergraph.schema.types["C"].interfaces.map(&:graphql_name).sort
    assert supergraph.schema.to_definition
  end

  def test_merges_inherited_interface_memberships
    skip unless minimum_graphql_version?("2.0.3")

    a = %{interface A { id:ID } interface AA implements A { id:ID } type C implements AA { id:ID } type Query { c:C }}
    b = %{interface B { id:ID } interface BB implements B { id:ID } type C implements BB { id:ID } type Query { c:C }}

    supergraph = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["A"], supergraph.schema.types["AA"].interfaces.map(&:graphql_name).sort
    assert_equal ["B"], supergraph.schema.types["BB"].interfaces.map(&:graphql_name).sort
    assert_equal ["A", "AA", "B", "BB"], supergraph.schema.types["C"].interfaces.map(&:graphql_name).sort
    assert supergraph.schema.to_definition
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

    supergraph = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["code", "id", "name"], supergraph.schema.types["I"].fields.keys.sort
    assert_equal ["code", "id", "name"], supergraph.schema.types["T"].fields.keys.sort
  end
end
