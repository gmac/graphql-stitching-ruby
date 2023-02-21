# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/shareables"

describe 'GraphQL::Stitching, shareables' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Shareables::ShareableA,
      "b" => Schemas::Shareables::ShareableB,
    })
  end

  def test_mutates_serially_and_stitches_results
    query = <<~GRAPHQL
      query {
        gadgetA(id: "1") {
          id
          name
          gizmo { a b c }
          uniqueToA
          uniqueToB
        }
        gadgetB(id: "1") {
          id
          name
          gizmo { a b c }
          uniqueToA
          uniqueToB
        }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, query)

    expected = {
      "data" => {
        "gadgetA" => {
          "id" => "1",
          "name" => "A1",
          "gizmo" => { "a" => "apple", "b" => "banana", "c" => "coconut" },
          "uniqueToA" => "AA",
          "uniqueToB" => "BB",
        },
       "gadgetB" => {
         "id" => "1",
         "name" => "B1",
         "gizmo" => { "a" => "aardvark", "b" => "bat", "c" => "cat" },
         "uniqueToA" => "AA",
         "uniqueToB" => "BB",
       },
     },
    }

    assert_equal expected, result
  end
end
