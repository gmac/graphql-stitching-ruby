# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/visibility"

describe 'GraphQL::Stitching, visibility' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Visibility::Alpha,
      "b" => Schemas::Visibility::Bravo,
    })
  end

  def test_some_stuff
    request = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ thingA(id: "1") { id size } }|,
      visibility_claims: [],
    )

    assert request.validate.any?

    request = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ thingA(id: "1") { id size } }|,
      visibility_claims: ["a"],
    )

    assert request.validate.none?
  end
end
