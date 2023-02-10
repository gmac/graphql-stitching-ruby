# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/errors"

describe 'GraphQL::Stitching, errors' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Errors::ElementsA,
      "b" => Schemas::Errors::ElementsB,
    })

    @query = <<~GRAPHQL
      query($ids: [ID!]!) {
        elementsA(ids: $ids) {
          name
          code
          year
        }
      }
    GRAPHQL
  end

  def test_queries_merged_interfaces
    result = plan_and_execute(@supergraph, @query, {
      "ids" => ["10", "18", "36"]
    }, false)

    expected_data = {
      "elementsA"=>[
        {"name"=>"neon", "_STITCH_id"=>"10", "_STITCH_typename"=>"Element", "code"=>"Ne", "year"=>1898},
        nil,
        {"name"=>"krypton", "_STITCH_id"=>"36", "_STITCH_typename"=>"Element"}
      ]
    }

    expected_errors = [
      { "message" => "Not found", "path" => ["elementsA", 1] },
      { "message" => "Not found", "path" => ["elementsA", 2] },
    ]

    assert_equal expected_data, result["data"]
    assert_equal expected_errors, result["errors"]
  end
end
