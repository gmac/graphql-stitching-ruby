# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/unions"

describe 'GraphQL::Stitching, unions' do
  def setup
    @supergraph = compose_definitions({
      "a" => TestSchema::Unions::SchemaA,
      "b" => TestSchema::Unions::SchemaB,
      "c" => TestSchema::Unions::SchemaC,
    })
  end

  def test_plan_abstract_merged_via_concrete_boundaries
    query = <<~GRAPHQL
      {
        fruitsA(ids: [\"1\", \"3\"]) {
          ...on Apple { a b c }
          ...on Banana { a b }
          ...on Coconut { b c }
        }
      }
    GRAPHQL

    expected = {
      "fruitsA" => [
        { "a" => "a1", "_STITCH_id" => "1", "_STITCH_typename" => "Apple", "b" => "b1", "c" => "c1" },
        { "a" => "a3", "_STITCH_id" => "3", "_STITCH_typename" => "Banana", "b" => "b3" },
      ],
    }

    result = plan_and_execute(@supergraph, query)
    assert_equal expected, result["data"]
  end

  def test_plan_abstract_merged_types_via_abstract_boundary
    query = <<~GRAPHQL
      {
        fruitsC(ids: [\"1\", \"4\"]) {
          ...on Apple { a b c }
          ...on Banana { a b }
          ...on Coconut { b c }
        }
      }
    GRAPHQL

    expected = {
      "fruitsC" => [
        { "c" => "c1", "_STITCH_id" => "1", "_STITCH_typename" => "Apple", "a" => "a1", "b" => "b1" },
        { "c" => "c4", "_STITCH_id" => "4", "_STITCH_typename" => "Coconut", "b" => "b4" },
      ],
    }

    result = plan_and_execute(@supergraph, query)
    assert_equal expected, result["data"]
  end
end
