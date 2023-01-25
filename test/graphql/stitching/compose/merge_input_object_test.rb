# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Compose, merging input objects' do

  def test_merges_input_object_descriptions
    a = %{"""a""" input Test { field:String } type Query { get(test:Test):String }}
    b = %{"""b""" input Test { field:String } type Query { get(test:Test):String }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.types["Test"].description
  end
end
