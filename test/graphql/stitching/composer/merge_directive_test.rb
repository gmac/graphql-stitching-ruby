# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging directives' do

  def test_merges_directive_definitions
    a = %|
      """a"""
      directive @fizzbuzz(a: String!) on OBJECT
      type Test @fizzbuzz(a: "A") { field: String }
      type Query { test: Test }
    |

    b = %|
      """b"""
      directive @fizzbuzz(a: String!, b: String) on OBJECT
      type Test @fizzbuzz(a: "A", b: "B") { field: String }
      type Query { test: Test }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    directive_definition = supergraph.schema.directives["fizzbuzz"]
    assert_equal "a/b", directive_definition.description
    assert_equal ["a"], directive_definition.arguments.keys
  end

  def test_combines_distinct_directives_assigned_to_an_element
    a = %|
      directive @fizz(arg: String!) on OBJECT
      directive @buzz on OBJECT
      type Test @fizz(arg: "a") @buzz { field: String }
      type Query { test:Test }
    |

    b = %|
      directive @fizz(arg: String!) on OBJECT
      directive @widget on OBJECT
      type Test @fizz(arg: "b") @widget { field: String }
      type Query { test:Test }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    directives = supergraph.schema.types["Test"].directives

    assert_equal 3, directives.length
    assert_equal ["buzz", "fizz", "widget"], directives.map(&:graphql_name).sort
    assert_equal "a/b", directives.find { _1.graphql_name == "fizz" }.arguments.keyword_arguments[:arg]
  end

  def test_omits_stitching_directives_and_includes_supergraph_directives
    a = %|
      directive @stitch(key: String!) repeatable on FIELD_DEFINITION
      type Test { id: ID! a: String }
      type Query { testA(id: ID!): Test @stitch(key: "id") }
    |

    b = %|
      directive @stitch(key: String!) repeatable on FIELD_DEFINITION
      type Test { id: ID! b: String }
      type Query { testB(id: ID!): Test @stitch(key: "id") }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert !supergraph.schema.directives.key?("stitch")
    assert supergraph.schema.directives.key?("key")
    assert supergraph.schema.directives.key?("resolver")
    assert supergraph.schema.directives.key?("source")
    assert_equal ["source"], supergraph.schema.query.get_field("testA").directives.map(&:graphql_name)
    assert_equal ["source"], supergraph.schema.query.get_field("testB").directives.map(&:graphql_name)
  end
end
