# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, root operations" do

  def setup
    @widgets_sdl = %|
      type Widget { id:ID! }
      type Query { widget: Widget }
      type Mutation { makeWidget: Widget }
      type Subscription { watchWidget: Widget }
    |

    @sprockets_sdl = %|
      type Sprocket { id:ID! }
      type Query { sprocket: Sprocket }
      type Mutation { makeSprocket: Sprocket }
      type Subscription { watchSprocket: Sprocket }
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

    plan = GraphQL::Stitching::Request.new(@supergraph, document).plan

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "widgets",
      operation_type: "query",
      selections: %|{ a: widget { id } c: widget { id } }|,
      path: [],
      if_type: nil,
      resolver: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: 0,
      location: "sprockets",
      operation_type: "query",
      selections: %|{ b: sprocket { id } d: sprocket { id } }|,
      path: [],
      if_type: nil,
      resolver: nil,
    }
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

    plan = GraphQL::Stitching::Request.new(@supergraph, document).plan

    assert_equal 3, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "widgets",
      operation_type: "mutation",
      selections: %|{ a: makeWidget { id } }|,
      path: [],
      if_type: nil,
      resolver: nil,
    }

    assert_keys plan.ops[1].as_json, {
      after: plan.ops[0].step,
      location: "sprockets",
      operation_type: "mutation",
      selections: %|{ b: makeSprocket { id } c: makeSprocket { id } }|,
      path: [],
      if_type: nil,
      resolver: nil,
    }

    assert_keys plan.ops[2].as_json, {
      after: plan.ops[1].step,
      location: "widgets",
      operation_type: "mutation",
      selections: %|{ d: makeWidget { id } e: makeWidget { id } }|,
      path: [],
      if_type: nil,
      resolver: nil,
    }
  end

  def test_plans_subscription_operations_for_single_field
    document = %|
      subscription {
        watchWidget { id }
      }
    |

    plan = GraphQL::Stitching::Request.new(@supergraph, document).plan

    assert_equal 1, plan.ops.length
    assert_keys plan.ops[0].as_json, {
      after: 0,
      location: "widgets",
      operation_type: "subscription",
      selections: %|{ watchWidget { id } }|,
      path: [],
      if_type: nil,
      resolver: nil,
    }
  end

  def test_raises_for_subscription_operations_with_multiple_fields
    document = %|
      subscription {
        a: watchWidget { id }
        b: watchSprocket { id }
      }
    |

    assert_error "Too many root fields" do
      GraphQL::Stitching::Request.new(@supergraph, document).plan
    end
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

    plan = GraphQL::Stitching::Request.new(@supergraph, document).plan

    assert_equal 2, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      location: "widgets",
      operation_type: "query",
      selections: %|{ a: widget { id } c: widget { id } e: widget { id } }|,
    }

    assert_keys plan.ops[1].as_json, {
      location: "sprockets",
      operation_type: "query",
      selections: %|{ b: sprocket { id } d: sprocket { id } f: sprocket { id } }|,
    }
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

    plan = GraphQL::Stitching::Request.new(@supergraph, document).plan

    assert_equal 4, plan.ops.length

    assert_keys plan.ops[0].as_json, {
      location: "widgets",
      selections: %|{ a: makeWidget { id } }|,
    }

    assert_keys plan.ops[1].as_json, {
      location: "sprockets",
      selections: %|{ b: makeSprocket { id } c: makeSprocket { id } }|,
    }

    assert_keys plan.ops[2].as_json, {
      location: "widgets",
      selections: %|{ d: makeWidget { id } e: makeWidget { id } }|,
    }

    assert_keys plan.ops[3].as_json, {
      location: "sprockets",
      selections: %|{ f: makeSprocket { id } }|,
    }
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
      request = GraphQL::Stitching::Request.new(supergraph, "#{operation_type} { a b c }")
      planner = GraphQL::Stitching::Planner.new(request)
      planner.perform

      first = planner.steps[0]
      assert_equal "a", first.location
      assert_equal "a", first.selections.first.name

      second = planner.steps[1]
      assert_equal "b", second.location
      assert_equal "b", second.selections.first.name

      third = planner.steps[2]
      assert_equal "c", third.location
      assert_equal "c", third.selections.first.name
    end
  end
end
