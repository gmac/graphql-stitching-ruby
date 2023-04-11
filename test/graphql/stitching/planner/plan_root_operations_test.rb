# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, root operations" do

  def setup
    @widgets_sdl = %|
      type Widget { id:ID! }
      type Query { widget: Widget }
      type Mutation { makeWidget: Widget }
    |

    @sprockets_sdl = %|
      type Sprocket { id:ID! }
      type Query { sprocket: Sprocket }
      type Mutation { makeSprocket: Sprocket }
    |

    @supergraph = compose_definitions({
      "widgets" => @widgets_sdl,
      "sprockets" => @sprockets_sdl,
    })
  end

  def test_plans_query_operations_by_async_location_groups
    document = %|
      query {
        a: widget { id }
        b: sprocket { id }
        c: widget { id }
        d: sprocket { id }
      }
    |

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(document),
    ).perform

    assert_equal 2, plan.operations.length

    first = plan.operations[0]
    assert_equal "widgets", first.location
    assert_equal "query", first.operation_type
    assert_equal "{ a: widget { id } c: widget { id } }", first.selection_set
    assert_equal 0, first.after
    assert_nil first.if_type

    second = plan.operations[1]
    assert_equal "sprockets", second.location
    assert_equal "query", second.operation_type
    assert_equal "{ b: sprocket { id } d: sprocket { id } }", second.selection_set
    assert_equal 0, second.after
    assert_nil second.if_type
  end

  def test_plans_mutation_operations_by_serial_location_groups
    document = %|
      mutation {
        a: makeWidget { id }
        b: makeSprocket { id }
        c: makeSprocket { id }
        d: makeWidget { id }
        e: makeWidget { id }
      }
    |

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(document),
    ).perform

    assert_equal 3, plan.operations.length

    first = plan.operations[0]
    assert_equal "widgets", first.location
    assert_equal "mutation", first.operation_type
    assert_equal "{ a: makeWidget { id } }", first.selection_set
    assert_equal 0, first.after
    assert_nil first.if_type

    second = plan.operations[1]
    assert_equal "sprockets", second.location
    assert_equal "mutation", second.operation_type
    assert_equal "{ b: makeSprocket { id } c: makeSprocket { id } }", second.selection_set
    assert_equal first.order, second.after
    assert_nil second.if_type

    third = plan.operations[2]
    assert_equal "widgets", third.location
    assert_equal "mutation", third.operation_type
    assert_equal "{ d: makeWidget { id } e: makeWidget { id } }", third.selection_set
    assert_equal second.order, third.after
    assert_nil third.if_type
  end

  def test_plans_root_queries_through_fragments
    document = %|
      fragment RootAttrs on Query {
        e: widget { id }
        f: sprocket { id }
      }
      query {
        a: widget { id }
        b: sprocket { id }
        ... {
          c: widget { id }
        }
        ...on Query {
          d: sprocket { id }
        }
        ...RootAttrs
      }
    |

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(document),
    ).perform

    assert_equal 2, plan.operations.length

    first = plan.operations[0]
    assert_equal "widgets", first.location
    assert_equal "{ a: widget { id } c: widget { id } e: widget { id } }", first.selection_set

    second = plan.operations[1]
    assert_equal "sprockets", second.location
    assert_equal "{ b: sprocket { id } d: sprocket { id } f: sprocket { id } }", second.selection_set
  end

  def test_plans_mutations_through_fragments
    document = %|
      fragment RootAttrs on Mutation {
        e: makeWidget { id }
        f: makeSprocket { id }
      }
      mutation {
        a: makeWidget { id }
        b: makeSprocket { id }
        ...on Mutation {
          c: makeSprocket { id }
          d: makeWidget { id }
        }
        ...RootAttrs
      }
    |

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(document),
    ).perform

    assert_equal 4, plan.operations.length

    first = plan.operations[0]
    assert_equal "widgets", first.location
    assert_equal "{ a: makeWidget { id } }", first.selection_set

    second = plan.operations[1]
    assert_equal "sprockets", second.location
    assert_equal "{ b: makeSprocket { id } c: makeSprocket { id } }", second.selection_set

    third = plan.operations[2]
    assert_equal "widgets", third.location
    assert_equal "{ d: makeWidget { id } e: makeWidget { id } }", third.selection_set

    second = plan.operations[3]
    assert_equal "sprockets", second.location
    assert_equal "{ f: makeSprocket { id } }", second.selection_set
  end

  def test_plans_root_fields_to_their_prioritized_location
    sdl = %|
      type Query { a: String b: String c: String }
      type Mutation { a: String b: String c: String }
    |

    supergraph = compose_definitions({ "a" => sdl, "b" => sdl, "c" => sdl }, {
      root_field_location_selector: ->(_locations, info) { info[:field_name] }
    })

    ["query", "mutation"].each do |operation_type|
      plan = GraphQL::Stitching::Planner.new(
        supergraph: supergraph,
        request: GraphQL::Stitching::Request.new("#{operation_type} { a b c }"),
      ).perform

      first = plan.operations[0]
      assert_equal "a", first.location
      assert_equal "a", first.selections.first.name

      second = plan.operations[1]
      assert_equal "b", second.location
      assert_equal "b", second.selections.first.name

      third = plan.operations[2]
      assert_equal "c", third.location
      assert_equal "c", third.selections.first.name
    end
  end
end
