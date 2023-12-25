# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, variables" do

  def setup
    @widgets_sdl = "
      input MakeWidgetInput { name: String child: MakeWidgetInput }
      type Widget { id:ID! name(lang: String): String }
      union Thing = Widget
      type Query { widget(id: ID!): Widget thing(id: ID!): Thing }
      type Mutation { makeWidget(input: MakeWidgetInput!): Widget }
    "

    @sprockets_sdl = "
      input MakeSprocketInput { name: String! child: MakeSprocketInput }
      type Sprocket { id:ID! name(lang: String): String }
      type Query { sprocket(id: ID!): Sprocket }
      type Mutation { makeSprocket(input: MakeSprocketInput!): Sprocket }
    "

    @supergraph = compose_definitions({
      "widgets" => @widgets_sdl,
      "sprockets" => @sprockets_sdl,
    })
  end

  def test_extracts_variables_from_field_arguments
    query = %|
      query($wid: ID!, $sid: ID!, $lang: String) {
        widget(id: $wid) { id name(lang: $lang) }
        sprocket(id: $sid) { id name(lang: $lang) }
      }
    |

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      query,
    ).plan

    assert_equal 2, plan.ops.length

    expected_vars = { "wid" => "ID!", "lang" => "String" }
    assert_equal expected_vars, plan.ops[0].variables

    expected_vars = { "sid" => "ID!", "lang" => "String" }
    assert_equal expected_vars, plan.ops[1].variables
  end

  def test_extracts_variables_from_field_directives
    query = %|
      query($a: String!, $b: String, $c: Int) {
        widget { id name @dir(a: $a, c: $c) }
        sprocket { id name @dir(b: $b, c: $c) }
      }
    |

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      query,
    ).plan

    assert_equal 2, plan.ops.length

    expected_vars = { "a" => "String!", "c" => "Int" }
    assert_equal expected_vars, plan.ops[0].variables

    expected_vars = { "b" => "String", "c" => "Int" }
    assert_equal expected_vars, plan.ops[1].variables
  end

  def test_extracts_variables_from_inline_input_objects
    mutation = %|
      mutation($wname1: String!, $wname2: String!, $sname1: String!, $sname2: String!, $lang: String) {
        makeWidget(input: { name: $wname1, child: { name: $wname2 } }) { id name(lang: $lang) }
        makeSprocket(input: { name: $sname1, child: { name: $sname2 } }) { id name(lang: $lang) }
      }
    |

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      mutation,
    ).plan

    assert_equal 2, plan.ops.length

    expected_vars = { "wname1" => "String!", "wname2" => "String!", "lang" => "String" }
    assert_equal expected_vars, plan.ops[0].variables

    expected_vars = { "sname1" => "String!", "sname2" => "String!", "lang" => "String" }
    assert_equal expected_vars, plan.ops[1].variables
  end

  def test_extracts_variables_for_input_object_fragments
    mutation = %|
      mutation($newWidget: MakeWidgetInput!, $newSprocket: MakeSprocketInput!, $lang: String) {
        makeWidget(input: $newWidget) { id name(lang: $lang) }
        makeSprocket(input: $newSprocket) { id name(lang: $lang) }
      }
    |

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      mutation,
    ).plan

    assert_equal 2, plan.ops.length

    expected_vars = { "newWidget" => "MakeWidgetInput!", "lang" => "String" }
    assert_equal expected_vars, plan.ops[0].variables

    expected_vars = { "newSprocket" => "MakeSprocketInput!", "lang" => "String" }
    assert_equal expected_vars, plan.ops[1].variables
  end

  def test_extracts_variables_from_inline_fragments
    query = %|
      query($wid: ID!, $lang: String) {
        thing(id: $wid) { ...on Widget { id name(lang: $lang) } }
      }
    |

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      query,
    ).plan

    assert_equal 1, plan.ops.length

    expected_vars = { "wid" => "ID!", "lang" => "String" }
    assert_equal expected_vars, plan.ops[0].variables
  end

  def test_extracts_variables_from_fragment_spreads
    query = %|
      query($wid: ID!, $lang: String) {
        thing(id: $wid) { ...WidgetAttrs }
      }
      fragment WidgetAttrs on Widget { id name(lang: $lang) }
    |

    plan = GraphQL::Stitching::Request.new(
      @supergraph,
      query,
    ).plan

    assert_equal 1, plan.ops.length

    expected_vars = { "wid" => "ID!", "lang" => "String" }
    assert_equal expected_vars, plan.ops[0].variables
  end
end
