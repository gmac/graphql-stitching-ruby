# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/errors"

describe 'GraphQL::Stitching::Shaper with nulls' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Errors::ElementsA,
    })
  end

  def test_queries_merged_interfaces
    query = query = <<~GRAPHQL
      query {
        elementsA(ids: ["54", "10"]) {
          name
        }
      }
    GRAPHQL

    raw_result = {"data"=>{"elementsA"=>[nil, {"name"=>"neon"}]}, "errors"=>[{"message"=>"Not found", "path"=>["elementsA", 0]}]}
    expected_result = {"data"=>{"elementsA"=>[{"name"=>"neon"}]}, "errors"=>[{"message"=>"Not found", "path"=>["elementsA", 0]}, {"message"=>"Cannot return null for non-nullable field Element.name"}]}

    result = GraphQL::Stitching::Shaper.new(
      supergraph: @supergraph,
      document: GraphQL::Stitching::Document.new(query),
      raw: raw_result
    ).perform!
    assert_equal expected_result, result
  end
end
