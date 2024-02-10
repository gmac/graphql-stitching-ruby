# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/nested_root"

describe 'GraphQL::Stitching, nested root scopes' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::NestedRoot::Alpha,
      "b" => Schemas::NestedRoot::Bravo,
    })
  end

  def test_nested_root_scopes
    source = %|
      mutation {
        doStuff {
          apple
          banana
        }
      }
    |

    expected = {
      "doStuff" => {
        "apple" => "red",
        "banana" => "yellow",
      }
    }

    result = plan_and_execute(@supergraph, source)
    assert_equal expected, result["data"]
  end

  def test_nested_root_scopes_with_complex_paths
    source = %|
      mutation {
        doThings {
          query {
            apple
            banana
          }
        }
      }
    |

    expected = {
      "doThings" => [
        {
          "query" => {
            "apple" => "red",
            "banana" => "yellow",
          }
        },
        {
          "query" => {
            "apple" => "red",
            "banana" => "yellow",
          }
        },
      ]
    }

    result = plan_and_execute(@supergraph, source)
    assert_equal expected, result["data"]
  end

  def test_nested_root_scopes_repath_errors
    source = %|
      mutation {
        doThing {
          query {
            errorA
            errorB
          }
        }
      }
    |

    expected = [
      { "message" => "a", "path" => ["doThing", "query", "errorA"] },
      { "message" => "b", "path" => ["doThing", "query", "errorB"] },
    ]

    result = plan_and_execute(@supergraph, source)
    assert_equal expected, result["errors"]
  end
end
