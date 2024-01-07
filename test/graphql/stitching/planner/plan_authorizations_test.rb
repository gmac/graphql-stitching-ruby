# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/authorizations"

describe "GraphQL::Stitching::Planner, abstract merged types" do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Authorizations::Alpha,
      "b" => Schemas::Authorizations::Bravo,
    })
  end

  def test_expands_interface_selections_for_target_location
    request = GraphQL::Stitching::Request.new(
      @supergraph,
      %|{ fruits(ids: ["1", "3"]) { id color price } }|,
      visibility_claims: ["read:price"],
      access_claims: ["read:coconut", "read:color"],
    )

    puts request.validate
    pp request.plan.as_json
  end
end
