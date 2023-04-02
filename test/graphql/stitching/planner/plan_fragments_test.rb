# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/conditionals"

describe "GraphQL::Stitching::Planner, fragments" do
  def setup
    @supergraph = compose_definitions({
      "exa" => Schemas::Conditionals::ExtensionsA,
      "exb" => Schemas::Conditionals::ExtensionsB,
      "base" => Schemas::Conditionals::Abstracts,
    })

    @expected_root_query = %|
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
    |
  end

  def test_plans_through_inline_fragments
    query = %|
      query($ids: [ID!]!) {
        fruits(ids: $ids) {
          ...on Apple { id extensions { color } }
          ...on Banana { id extensions { shape } }
        }
      }
    |

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(query),
    ).perform

    assert_equal 3, plan.operations.length

    first = plan.operations[0]
    assert_equal "base", first.location
    assert_equal squish_string(@expected_root_query), first.selection_set

    second = plan.operations[1]
    assert_equal "exa", second.location
    assert_equal "{ color }", second.selection_set
    assert_equal "AppleExtension", second.type_condition
    assert_equal ["fruits", "extensions"], second.insertion_path
    assert_equal first.order, second.after

    third = plan.operations[2]
    assert_equal "exb", third.location
    assert_equal "{ shape }", third.selection_set
    assert_equal "BananaExtension", third.type_condition
    assert_equal ["fruits", "extensions"], third.insertion_path
    assert_equal first.order, third.after
  end

  def test_plans_through_fragment_spreads
    query = %|
      query($ids: [ID!]!) {
        fruits(ids: $ids) {
          ...AppleAttrs
          ...BananaAttrs
        }
      }
      fragment AppleAttrs on Apple { id extensions { color } }
      fragment BananaAttrs on Banana { id extensions { shape } }
    |

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(query),
    ).perform

    assert_equal 3, plan.operations.length

    first = plan.operations[0]
    assert_equal "base", first.location
    assert_equal squish_string(@expected_root_query), first.selection_set

    second = plan.operations[1]
    assert_equal "exa", second.location
    assert_equal "{ color }", second.selection_set
    assert_equal "AppleExtension", second.type_condition
    assert_equal ["fruits", "extensions"], second.insertion_path
    assert_equal first.order, second.after

    third = plan.operations[2]
    assert_equal "exb", third.location
    assert_equal "{ shape }", third.selection_set
    assert_equal "BananaExtension", third.type_condition
    assert_equal ["fruits", "extensions"], third.insertion_path
    assert_equal first.order, third.after
  end

  def test_plans_repeat_selections_and_fragments_into_coalesced_groupings
    alpha = %|
      type Test { id:ID! a: String x: Int y: Int }
      type Query { testA(id: ID!): Test! @stitch(key: "id") }
    |

    bravo = %|
      type Test { id:ID! b: String }
      type Namespace { test: Test }
      type Query { namespace: Namespace! testB(id: ID!): Test! @stitch(key: "id") }
    |

    query = %|
      query {
        namespace {
          test { a }
          test { b }
          test { ...on Test { x } ...TestAttrs }
        }
      }
      fragment TestAttrs on Test { y }
    |

    @supergraph = compose_definitions({ "alpha" => alpha, "bravo" => bravo })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(query),
    ).perform

    assert_equal 2, plan.operations.length

    first = plan.operations[0]
    assert_equal "bravo", first.location

    second = plan.operations[1]
    assert_equal "alpha", second.location
    assert_equal ["namespace", "test"], second.insertion_path
    assert_equal "{ a x y }", second.selection_set
  end
end
