# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging scalars' do

  def test_merges_scalar_descriptions
    a = %{"""a""" scalar URL type Query { url:URL }}
    b = %{"""b""" scalar URL type Query { url:URL }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.types["URL"].description
  end
end
