# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/conditionals"

describe "GraphQL::Stitching::Planner, fragments" do
  def setup
    @supergraph = compose_definitions({
      "base" => Schemas::Conditionals::Abstracts,
      "ext" => Schemas::Conditionals::Extensions,
    })

    @expected_root_query = <<~GRAPHQL
      {
        fruits(ids: $ids) {
          ... on Apple {
            id
            extensions {
              _STITCH_id: id
              _STITCH_typename: __typename
            }
          }
          ... on Banana {
            id
            extensions {
              _STITCH_id: id
              _STITCH_typename: __typename
            }
          }
          _STITCH_typename: __typename
        }
      }
    GRAPHQL
  end

  def test_plans_through_inline_fragments
    query = <<~GRAPHQL
      query($ids: [ID!]!) {
        fruits(ids: $ids) {
          ...on Apple { id extensions { color } }
          ...on Banana { id extensions { shape } }
        }
      }
    GRAPHQL

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      document: GraphQL::Stitching::Document.new(query),
    ).perform

    assert_equal 3, plan.operations.length

    first = plan.operations[0]
    assert_equal "base", first.location
    assert_equal squish_string(@expected_root_query), first.selection_set

    second = plan.operations[1]
    assert_equal "ext", second.location
    assert_equal "{ color }", second.selection_set
    assert_equal "AppleExtension", second.type_condition
    assert_equal ["fruits", "extensions"], second.insertion_path
    assert_equal first.key, second.after_key

    third = plan.operations[2]
    assert_equal "ext", third.location
    assert_equal "{ shape }", third.selection_set
    assert_equal "BananaExtension", third.type_condition
    assert_equal ["fruits", "extensions"], third.insertion_path
    assert_equal first.key, third.after_key
  end

  def test_plans_through_fragment_spreads
    query = <<~GRAPHQL
      query($ids: [ID!]!) {
        fruits(ids: $ids) {
          ...AppleAttrs
          ...BananaAttrs
        }
      }
      fragment AppleAttrs on Apple { id extensions { color } }
      fragment BananaAttrs on Banana { id extensions { shape } }
    GRAPHQL

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      document: GraphQL::Stitching::Document.new(query),
    ).perform

    assert_equal 3, plan.operations.length

    first = plan.operations[0]
    assert_equal "base", first.location
    assert_equal squish_string(@expected_root_query), first.selection_set

    second = plan.operations[1]
    assert_equal "ext", second.location
    assert_equal "{ color }", second.selection_set
    assert_equal "AppleExtension", second.type_condition
    assert_equal ["fruits", "extensions"], second.insertion_path
    assert_equal first.key, second.after_key

    third = plan.operations[2]
    assert_equal "ext", third.location
    assert_equal "{ shape }", third.selection_set
    assert_equal "BananaExtension", third.type_condition
    assert_equal ["fruits", "extensions"], third.insertion_path
    assert_equal first.key, third.after_key
  end
end
