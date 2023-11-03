# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Executor" do
  def mock_execs(source, returns, operation_name: nil, variables: nil)
    alpha = %|
      #{STITCH_DEFINITION}
      directive @inContext(lang: String!) on QUERY \| MUTATION
      type Product { id: ID! name: String }
      type Query { product(id: ID!): Product @stitch(key: "id") }
    |
    bravo = %|
      type Product { id: ID! }
      type Query { featured: [Product!]! }
    |

    results = []
    supergraph = GraphQL::Stitching::Composer.new.perform({
      alpha: {
        schema: GraphQL::Schema.from_definition(alpha),
        executable: -> (loc, src, vars, ctx) {
          results << { location: loc, source: src }
          { "data" => returns.shift }
        },
      },
      bravo: {
        schema: GraphQL::Schema.from_definition(bravo),
        executable: -> (loc, src, vars, ctx) {
          results << { location: loc, source: src }
          { "data" => returns.shift }
        },
      },
    })

    request = GraphQL::Stitching::Request.new(
      source,
      operation_name: operation_name,
      variables: variables,
    ).prepare!

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      request: request,
    ).perform

    GraphQL::Stitching::Executor.new(
      supergraph: supergraph,
      request: request,
      plan: plan,
    ).perform

    results
  end

  def test_with_batching
    req = %|{ featured { name } }|

    expected1 = %|
      query{ featured { _export_id: id _export___typename: __typename } }
    |
    expected2 = %|
      query{
        _0_0_result: product(id:"1") { name }
        _0_1_result: product(id:"2") { name }
        _0_2_result: product(id:"3") { name }
      }
    |

    execs = mock_execs(req, [
      {
        "featured" => [
          { "_export_id" => "1", "_export___typename" => "Product" },
          { "_export_id" => "2", "_export___typename" => "Product" },
          { "_export_id" => "3", "_export___typename" => "Product" },
        ]
      },
      {
        "_0_0_result" => { "name" => "Potato" },
        "_0_1_result" => { "name" => "Carrot" },
        "_0_2_result" => { "name" => "Turnip" },
      },
    ])

    assert_equal 2, execs.length

    assert_equal "bravo", execs[0][:location]
    assert_equal squish_string(expected1), execs[0][:source]

    assert_equal "alpha", execs[1][:location]
    assert_equal squish_string(expected2), execs[1][:source]
  end

  def test_with_operation_name_and_directives
    req = %|query Test @inContext(lang: "EN") { featured { name } }|

    expected1 = %|
      query Test_1 @inContext(lang: "EN") { featured { _export_id: id _export___typename: __typename } }
    |
    expected2 = %|
      query Test_2 @inContext(lang: "EN") { _0_0_result: product(id:"1") { name } }
    |

    execs = mock_execs(req, [
      { "featured" => [{ "_export_id" => "1", "_export___typename" => "Product" }] },
      { "_0_0_result" => { "name" => "Potato" } },
    ], operation_name: "Test")

    assert_equal 2, execs.length

    assert_equal "bravo", execs[0][:location]
    assert_equal squish_string(expected1), execs[0][:source]

    assert_equal "alpha", execs[1][:location]
    assert_equal squish_string(expected2), execs[1][:source]
  end
end
