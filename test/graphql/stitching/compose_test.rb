# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::ComposeTest < Minitest::Test

  def test_errors_for_merged_types_of_different_kinds
    a = "type Query { a:Boom } type Boom { a:String }"
    b = "type Query { b:Boom } interface Boom { b:String }"

    assert_error('Cannot merge different kinds for `Boom`. Found: OBJECT, INTERFACE', ComposeError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end
end