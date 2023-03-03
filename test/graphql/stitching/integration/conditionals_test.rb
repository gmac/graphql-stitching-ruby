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
        },
        "__typename" => "Apple",
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
        },
        "__typename" => "Apple",
      }, {
        "extensions" => {
          "shape" => "crescent",
        },
        "__typename" => "Banana",
      }],
    }

    assert_equal expected, result["data"]
  end

  def test_performs_specific_queries_planned_for_the_returned_type_via_fragment
    @query = <<~GRAPHQL
      query($ids: [ID!]!) {
        fruits(ids: $ids) {
          ...on HasExtension {
            abstractExtension {
              ...on AppleExtension { color }
              ...on BananaExtension { shape }
            }
          }
        }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, @query, {
      "ids" => ["1"]
    }) do |_planner, executor|
      assert_equal 2, executor.query_count
    end

    expected = {
      "fruits" => [{
        "abstractExtension" => {
          "color" => "red",
        }
      }]
    }

    assert_equal expected, result["data"]
  end

  def test_performs_all_queries_for_all_returned_types_via_fragment
    @query = <<~GRAPHQL
      query($ids: [ID!]!) {
        fruits(ids: $ids) {
          ...on HasExtension {
            abstractExtension {
              ...ExtFields
            }
          }
        }
      }
      fragment ExtFields on Extension {
        ...on AppleExtension { color }
        ...on BananaExtension { shape }
      }
    GRAPHQL

    result = plan_and_execute(@supergraph, @query, {
      "ids" => ["1", "2"]
    }) do |_planner, executor|
      assert_equal 3, executor.query_count
    end

    expected = {
      "fruits" => [{
        "abstractExtension" => {
          "color" => "red",
        }
      }, {
        "abstractExtension" => {
          "shape" => "crescent",
        }
      }]
    }

    assert_equal expected, result["data"]
  end
end
