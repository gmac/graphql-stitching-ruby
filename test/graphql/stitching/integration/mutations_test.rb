# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/mutations"

describe 'GraphQL::Stitching, mutations' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Mutations::MutationsA,
      "b" => Schemas::Mutations::MutationsB,
    })
  end

  def test_mutates_serially_and_stitches_results
    Schemas::Mutations.reset

    mutations = <<~GRAPHQL
      mutation AddRecords {
        first:  addViaA { id via a b }
        second: addViaB { id via a b }
        third:  addViaB { id via a b }
        fourth: addViaA { id via a b }
        fifth:  addViaA { id via a b }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, mutations)

    expected = {
      "data" => {
        "first"  => { "id" => "1", "via" => "A", "a" => "A1", "b" => "B1" },
        "second" => { "id" => "2", "via" => "B", "a" => "A2", "b" => "B2" },
        "third"  => { "id" => "3", "via" => "B", "a" => "A3", "b" => "B3" },
        "fourth" => { "id" => "4", "via" => "A", "a" => "A4", "b" => "B4" },
        "fifth"  => { "id" => "5", "via" => "A", "a" => "A5", "b" => "B5" },
      },
    }

    assert_equal expected, result
    assert_equal ["1", "2", "3", "4", "5"], Schemas::Mutations.creation_order
  end
end
