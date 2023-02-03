# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, variables" do

  def setup
    @widgets_sdl = "
      input MakeWidgetInput { name: String child: MakeWidgetInput }
      type Widget { id:ID! name(lang: String): String }
      type Query { widget(id: ID!): Widget }
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
    document = "
      query($wid: ID!, $sid: ID!, $lang: String) {
        widget(id: $wid) { id name(lang: $lang) }
        sprocket(id: $sid) { id name(lang: $lang) }
      }
    "

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      document: GraphQL::Stitching::Document.new(document),
    ).perform

    assert_equal 2, plan.operations.length

    expected_vars = { "wid" => "ID!", "lang" => "String" }
    assert_equal expected_vars, plan.operations[0].variable_set

    expected_vars = { "sid" => "ID!", "lang" => "String" }
    assert_equal expected_vars, plan.operations[1].variable_set
  end

  def test_extracts_variables_from_inline_input_objects
    document = "
      mutation($wname1: String!, $wname2: String!, $sname1: String!, $sname2: String!, $lang: String) {
        makeWidget(input: { name: $wname1, child: { name: $wname2 } }) { id name(lang: $lang) }
        makeSprocket(input: { name: $sname1, child: { name: $sname2 } }) { id name(lang: $lang) }
      }
    "

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      document: GraphQL::Stitching::Document.new(document),
    ).perform

    assert_equal 2, plan.operations.length

    expected_vars = { "wname1" => "String!", "wname2" => "String!", "lang" => "String" }
    assert_equal expected_vars, plan.operations[0].variable_set

    expected_vars = { "sname1" => "String!", "sname2" => "String!", "lang" => "String" }
    assert_equal expected_vars, plan.operations[1].variable_set
  end

  def test_extracts_variables_for_input_object_fragments
    document = "
      mutation($newWidget: MakeWidgetInput!, $newSprocket: MakeSprocketInput!, $lang: String) {
        makeWidget(input: $newWidget) { id name(lang: $lang) }
        makeSprocket(input: $newSprocket) { id name(lang: $lang) }
      }
    "

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      document: GraphQL::Stitching::Document.new(document),
    ).perform

    assert_equal 2, plan.operations.length

    expected_vars = { "newWidget" => "MakeWidgetInput!", "lang" => "String" }
    assert_equal expected_vars, plan.operations[0].variable_set

    expected_vars = { "newSprocket" => "MakeSprocketInput!", "lang" => "String" }
    assert_equal expected_vars, plan.operations[1].variable_set
  end

  def test_extracts_variables_from_inline_fragments
    # @todo
  end

  def test_extracts_variables_from_fragment_spreads
    # @todo
  end
end
