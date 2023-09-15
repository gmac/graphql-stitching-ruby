# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/federation"

describe "GraphQL::Stitching::Federation" do

  def test_federation_to_stitching
    @supergraph = compose_definitions({
      "federation" => Schemas::Federation::Federation1,
      "stitching" => Schemas::Federation::Stitching,
    })

    query = %|
      query {
        widgets(upcs: ["1"]) {
          megahertz
          model
          sprockets {
            cogs
            diameter
          }
        }
      }
    |

    expected = {
      "data" => {
        "widgets" => [{
          "megahertz" => 3,
          "model" => "Basic",
          "sprockets" => [
            { "cogs" => 23, "diameter" => 77 },
            { "cogs" => 14, "diameter" => 20 },
          ],
        }],
      },
    }

    result = plan_and_execute(@supergraph, query) do |plan|
      assert_equal ["stitching", "federation", "stitching"], plan.ops.map(&:location)
    end

    assert_equal expected, result
  end

  def test_federation_to_federation
    @supergraph = compose_definitions({
      "federation1" => Schemas::Federation::Federation1,
      "federation2" => Schemas::Federation::Federation2,
    })

    query = %|
      query {
        widget {
          megahertz
          model
          sprockets {
            cogs
            diameter
          }
        }
      }
    |

    expected = {
      "data" => {
        "widget" => {
          "megahertz" => 3,
          "model" => "Basic",
          "sprockets" => [
            { "cogs" => 23, "diameter" => 77 },
            { "cogs" => 14, "diameter" => 20 },
          ],
        },
      },
    }

    result = plan_and_execute(@supergraph, query) do |plan|
      assert_equal ["federation2", "federation1", "federation2"], plan.ops.map(&:location)
    end

    assert_equal expected, result
  end
end
