# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/errors"

describe 'GraphQL::Stitching, errors' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Errors::ElementsA,
      "b" => Schemas::Errors::ElementsB,
    })
  end

  def test_repaths_root_errors
    result = plan_and_execute(@supergraph, %|
      query {
        elementsA(ids: ["10", "18", "36"]) {
          name
          code
          year
        }
      }
    |)

    expected_data = {
      "elementsA" => [
        {
          "name" => "neon",
          "code" => "Ne",
          "year" => 1898,
        },
        nil,
        {
          "name" => "krypton",
          "code" => nil,
          "year" => nil,
        },
      ],
    }

    expected_errors = [
      { "message" => "Not found", "path" => ["elementsA", 1] },
      { "message" => "Not found", "path" => ["elementsA", 2] },
    ]

    assert_equal expected_data, result["data"]
    assert_equal expected_errors, result["errors"]
  end

  def test_repaths_nested_errors_onto_list_source
    result = plan_and_execute(@supergraph, %|
      query {
        elementsA(ids: ["10", "36"]) {
          name
          isotopes {
            name
            halflife
          }
          isotope {
            name
            halflife
          }
        }
      }
    |)

    expected_data = {
      "elementsA" => [
        {
          "name" => "neon",
          "isotope" => nil,
          "isotopes" => [nil],
        },
        {
          "name" => "krypton",
          "isotope" => { "name" => "Kr79", "halflife" => "35d" },
          "isotopes" => [{ "name" => "Kr79", "halflife" => "35d" }],
        },
      ],
    }

    expected_errors = [
      { "message" => "Not found", "path" => ["elementsA", 0, "isotopes", 0] },
      { "message" => "Not found", "path" => ["elementsA", 0, "isotope"] },
    ]

    assert_equal expected_data, result["data"]
    assert_equal expected_errors, result["errors"]
  end

  def test_repaths_nested_errors_onto_object_source
    result = plan_and_execute(@supergraph, %|
      query {
        elementA(id: "10") {
          name
          isotopes {
            name
            halflife
          }
          isotope {
            name
            halflife
          }
        }
      }
    |)

    expected_data = {
      "elementA" => {
        "name" => "neon",
        "isotope" => nil,
        "isotopes" => [nil],
      },
    }

    expected_errors = [
      { "message" => "Not found", "path" => ["elementA", "isotopes", 0] },
      { "message" => "Not found", "path" => ["elementA", "isotope"] },
    ]

    assert_equal expected_data, result["data"]
    assert_equal expected_errors, result["errors"]
  end
end
