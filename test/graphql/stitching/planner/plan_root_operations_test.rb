# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Plan, root operations" do

  WIDGETS = "
    type Widget { id:ID! }
    type Query { widget: Widget }
    type Mutation { makeWidget: Widget }
  "

  SPROCKETS = "
    type Sprocket { id:ID! }
    type Query { sprocket: Sprocket }
    type Mutation { makeSprocket: Sprocket }
  "

  GRAPH_CONTEXT = compose_definitions({ "widgets" => WIDGETS, "sprockets" => SPROCKETS })

  def test_plans_by_given_operation_name
    document = GraphQL.parse("query First { widget { id } } query Second { sprocket { id } }")

    plan1 = GraphQL::Stitching::Plan.new(
      graph_info: GRAPH_CONTEXT,
      document: document,
      operation_name: "First",
    ).plan

    assert_equal 1, plan1.operations.length
    assert_equal "widget", plan1.operations.first.selections.first.name

    plan2 = GraphQL::Stitching::Plan.new(
      graph_info: GRAPH_CONTEXT,
      document: document,
      operation_name: "Second",
    ).plan

    assert_equal 1, plan2.operations.length
    assert_equal "sprocket", plan2.operations.first.selections.first.name
  end

  def test_errors_for_multiple_operations_given_without_operation_name
    document = GraphQL.parse("query First { widget { id } } query Second { sprocket { id } }")

    assert_error "An operation name is required" do
      GraphQL::Stitching::Plan.new(
        graph_info: GRAPH_CONTEXT,
        document: document,
      ).plan
    end
  end

  def test_errors_for_invalid_operation_names
    document = GraphQL.parse("query First { widget { id } } query Second { sprocket { id } }")

    assert_error "Invalid root operation" do
      GraphQL::Stitching::Plan.new(
        graph_info: GRAPH_CONTEXT,
        document: document,
        operation_name: "Invalid",
      ).plan
    end
  end

  def test_errors_for_invalid_operation_types
    graph_info = compose_definitions({ "widgets" => WIDGETS, "sprockets" => SPROCKETS })
    graph_info.schema.subscription(graph_info.schema.get_type("Widget"))
    document = GraphQL.parse("subscription { id }")

    assert_error "Invalid root operation" do
      GraphQL::Stitching::Plan.new(
        graph_info: GRAPH_CONTEXT,
        document: document,
      ).plan
    end
  end

  def test_plans_query_operations_by_async_location_groups
    document = "
      query {
        a: widget { id }
        b: sprocket { id }
        c: widget { id }
        d: sprocket { id }
      }
    "

    plan = GraphQL::Stitching::Plan.new(
      graph_info: GRAPH_CONTEXT,
      document: GraphQL.parse(document),
    ).plan

    assert_equal 2, plan.operations.length
    assert_equal "widgets", plan.operations[0].location
    assert_equal ["a", "c"], plan.operations[0].selections.map(&:alias)

    assert_equal "sprockets", plan.operations[1].location
    assert_equal ["b", "d"], plan.operations[1].selections.map(&:alias)
  end

  def test_plans_mutation_operations_by_serial_location_groups
    document = "
      mutation {
        a: makeWidget { id }
        b: makeSprocket { id }
        c: makeSprocket { id }
        d: makeWidget { id }
        e: makeWidget { id }
      }
    "

    plan = GraphQL::Stitching::Plan.new(
      graph_info: GRAPH_CONTEXT,
      document: GraphQL.parse(document),
    ).plan

    assert_equal 3, plan.operations.length
    assert_equal "widgets", plan.operations[0].location
    assert_equal ["a"], plan.operations[0].selections.map(&:alias)

    assert_equal "sprockets", plan.operations[1].location
    assert_equal ["b", "c"], plan.operations[1].selections.map(&:alias)

    assert_equal "widgets", plan.operations[2].location
    assert_equal ["d", "e"], plan.operations[2].selections.map(&:alias)
  end
end
