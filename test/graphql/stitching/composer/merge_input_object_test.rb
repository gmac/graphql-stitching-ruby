# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging input objects' do

  def test_merges_input_object_descriptions
    a = %{"""a""" input Test { field:String } type Query { get(test:Test):String }}
    b = %{"""b""" input Test { field:String } type Query { get(test:Test):String }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.types["Test"].description
  end

  def test_merges_input_object_and_field_directives
    a = %|
      directive @fizzbuzz(arg: String!) on INPUT_OBJECT \| INPUT_FIELD_DEFINITION
      input Test @fizzbuzz(arg: "a") { field:String @fizzbuzz(arg: "a") }
      type Query { get(test:Test):String }
    |

    b = %|
      directive @fizzbuzz(arg: String!) on INPUT_OBJECT \| INPUT_FIELD_DEFINITION
      input Test @fizzbuzz(arg: "b") { field:String @fizzbuzz(arg: "b") }
      type Query { get(test:Test):String }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.types["Test"].directives.first.arguments.keyword_arguments[:arg]
    assert_equal "a/b", supergraph.schema.types["Test"].arguments["field"].directives.first.arguments.keyword_arguments[:arg]
  end
end
