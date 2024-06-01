# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/unions"

describe 'GraphQL::Stitching, unions' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Unions::SchemaA,
      "b" => Schemas::Unions::SchemaB,
      "c" => Schemas::Unions::SchemaC,
    })
  end

  def test_plan_abstract_merged_via_concrete_resolvers
    query = %|
      {
        fruitsA(ids: ["1", "3"]) {
          ...on Apple { a b c }
          ...on Banana { a b }
          ...on Coconut { b c }
        }
      }
    |

    expected = {
      "fruitsA" => [
        { "a" => "a1", "b" => "b1", "c" => "c1" },
        { "a" => "a3", "b" => "b3" },
      ],
    }

    result = plan_and_execute(@supergraph, query)
    assert_equal expected, result["data"]
  end

  def test_plan_abstract_merged_types_via_abstract_resolver
    query = %|
      {
        fruitsC(ids: ["1", "4"]) {
          ...on Apple { a b c }
          ...on Banana { a b }
          ...on Coconut { b c }
        }
      }
    |

    expected = {
      "fruitsC" => [
        { "c" => "c1", "a" => "a1", "b" => "b1" },
        { "c" => "c4", "b" => "b4" },
      ],
    }

    result = plan_and_execute(@supergraph, query)
    assert_equal expected, result["data"]
  end
end
