# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, delegation strategies" do

  # Fields a + b select together
  alpha_sdl = %|
    type Widget { id: ID! a: String! b: String! }
    type Query { alpha(id: ID!): Widget @stitch(key: "id") }
  |

  bravo_sdl = %|
    type Widget { id: ID! a: String! b: String! }
    type Query { bravo(id: ID!): Widget @stitch(key: "id") }
  |

  # Field c is unique to one location
  # Field d joins location already used for c
  charlie_sdl = %|
    type Widget { id: ID! c: String! d: String! }
    type Query { charlie(id: ID!): Widget @stitch(key: "id") }
  |

  delta_sdl = %|
    type Widget { id: ID! d: String! e: String! }
    type Query { delta(id: ID!): Widget @stitch(key: "id") }
  |

  # Fields e + f go to highest availability
  echo_sdl = %|
    type Widget { id: ID! d: String! e: String! f: String! }
    type Query { echo(id: ID!): Widget @stitch(key: "id") }
  |

  foxtrot_sdl = %|
    type Widget { id: ID! d: String! f: String! }
    type Query { foxtrot(id: ID!): Widget @stitch(key: "id") }
  |

  SUPERGRAPH = compose_definitions({
    "alpha" => alpha_sdl,
    "bravo" => bravo_sdl,
    "charlie" => charlie_sdl,
    "delta" => delta_sdl,
    "echo" => echo_sdl,
    "foxtrot" => foxtrot_sdl,
  })

  def test_delegates_common_fields_to_current_routing_location
    plan1 = GraphQL::Stitching::Planner.new(
      supergraph: SUPERGRAPH,
      request: GraphQL::Stitching::Request.new('query { alpha(id: "1") { a b } }'),
    ).perform

    op1 = plan1.ops[0]
    assert_equal "alpha", op1.location
    assert_equal %|{ alpha(id: \"1\") { a b } }|, op1.selections

    plan2 = GraphQL::Stitching::Planner.new(
      supergraph: SUPERGRAPH,
      request: GraphQL::Stitching::Request.new('query { bravo(id: "1") { a b } }'),
    ).perform

    op2 = plan2.ops[0]
    assert_equal "bravo", op2.location
    assert_equal %|{ bravo(id: \"1\") { a b } }|, op2.selections
  end

  def test_delegates_remote_selections_by_unique_location_then_used_location_then_highest_availability
    plan = GraphQL::Stitching::Planner.new(
      supergraph: SUPERGRAPH,
      request: GraphQL::Stitching::Request.new('query { alpha(id: "1") { a b c d e f } }'),
    ).perform

    assert_equal 3, plan.ops.length

    first = plan.ops[0]
    assert_equal "alpha", first.location
    assert_equal %|{ alpha(id: \"1\") { a b _STITCH_id: id _STITCH_typename: __typename } }|, first.selections

    second = plan.ops[1]
    assert_equal "charlie", second.location
    assert_equal "{ c d }", second.selections
    assert_equal first.step, second.after

    third = plan.ops[2]
    assert_equal "echo", third.location
    assert_equal "{ e f }", third.selections
    assert_equal first.step, third.after
  end
end
