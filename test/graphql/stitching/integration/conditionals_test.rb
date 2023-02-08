# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/conditionals"

describe 'GraphQL::Stitching, type conditions' do
  def setup
    @supergraph = compose_definitions({
      "exa" => Schemas::Conditionals::ExtensionsA,
      "exb" => Schemas::Conditionals::ExtensionsB,
      "base" => Schemas::Conditionals::Abstracts,
    })

    @query = <<~GRAPHQL
      query($ids: [ID!]!) {
        fruits(ids: $ids) {
          ...on Apple { extensions { color } }
          ...on Banana { extensions { shape } }
          __typename
        }
      }
    GRAPHQL
  end

  def test_performs_specific_queries_planned_for_the_returned_type
    result = plan_and_execute(@supergraph, @query, {
      "ids" => ["1"]
    }) do |_planner, executor|
      assert_equal 2, executor.query_count
    end

    expected = {
      "fruits" => [{
        "extensions" => {
          "color" => "red",
          "_STITCH_id" => "11",
          "_STITCH_typename" => "AppleExtension"
        },
        "__typename" => "Apple",
        "_STITCH_typename" => "Apple",
      }],
    }

    assert_equal expected, result["data"]
  end

  def test_performs_all_queries_for_all_returned_types
    result = plan_and_execute(@supergraph, @query, {
      "ids" => ["1", "2"]
    }) do |_planner, executor|
      assert_equal 3, executor.query_count
    end

    expected = {
      "fruits" => [{
        "extensions" => {
          "color" => "red",
          "_STITCH_id" => "11",
          "_STITCH_typename" => "AppleExtension"
        },
        "__typename" => "Apple",
        "_STITCH_typename" => "Apple",
      }, {
        "extensions" => {
          "shape" => "crescent",
          "_STITCH_id" => "22",
          "_STITCH_typename" => "BananaExtension"
        },
        "__typename" => "Banana",
        "_STITCH_typename" => "Banana",
      }],
    }

    assert_equal expected, result["data"]
  end
end
