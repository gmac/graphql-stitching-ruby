# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, general concerns' do
  def test_errors_for_merged_types_of_different_kinds
    a = "type Query { a:Boom } type Boom { a:String }"
    b = "type Query { b:Boom } interface Boom { b:String }"

    assert_error('Cannot merge different kinds for `Boom`. Found: OBJECT, INTERFACE', ComposerError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end
end
