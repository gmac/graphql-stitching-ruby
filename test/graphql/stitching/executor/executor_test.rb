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
        executable: -> (req, src, vars) {
          results << { location: "alpha", source: src, variables: vars }
          { "data" => returns.shift }
        },
      },
      bravo: {
        schema: GraphQL::Schema.from_definition(bravo),
        executable: -> (req, src, vars) {
          results << { location: "bravo", source: src, variables: vars }
          { "data" => returns.shift }
        },
      },
    })

    GraphQL::Stitching::Request.new(
      supergraph,
      source,
      operation_name: operation_name,
      variables: variables,
    ).prepare!.execute

    results
  end

  def test_with_batching
    req = %|{ featured { name } }|

    expected_source1 = %|
      query{ featured { _export_id: id _export___typename: __typename } }
    |
    expected_source2 = %|
      query($_0_0_key_0:ID!,$_0_1_key_0:ID!,$_0_2_key_0:ID!){
        _0_0_result: product(id:$_0_0_key_0) { name }
        _0_1_result: product(id:$_0_1_key_0) { name }
        _0_2_result: product(id:$_0_2_key_0) { name }
      }
    |

    expected_vars1 = {}
    expected_vars2 = {
      "_0_0_key_0" => "1",
      "_0_1_key_0" => "2",
      "_0_2_key_0" => "3",
    }

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
    assert_equal squish_string(expected_source1), execs[0][:source]
    assert_equal expected_vars1, execs[0][:variables]

    assert_equal "alpha", execs[1][:location]
    assert_equal squish_string(expected_source2), execs[1][:source]
    assert_equal expected_vars2, execs[1][:variables]
  end

  def test_with_operation_name_and_directives
    req = %|query Test @inContext(lang: "EN") { featured { name } }|

    expected_source1 = %|
      query Test_1 @inContext(lang: "EN") { featured { _export_id: id _export___typename: __typename } }
    |
    expected_source2 = %|
      query Test_2($_0_0_key_0:ID!) @inContext(lang: "EN") { _0_0_result: product(id:$_0_0_key_0) { name } }
    |

    expected_vars1 = {}
    expected_vars2 = {
      "_0_0_key_0" => "1",
    }

    execs = mock_execs(req, [
      { "featured" => [{ "_export_id" => "1", "_export___typename" => "Product" }] },
      { "_0_0_result" => { "name" => "Potato" } },
    ], operation_name: "Test")

    assert_equal 2, execs.length

    assert_equal "bravo", execs[0][:location]
    assert_equal squish_string(expected_source1), execs[0][:source]
    assert_equal expected_vars1, execs[0][:variables]

    assert_equal "alpha", execs[1][:location]
    assert_equal squish_string(expected_source2), execs[1][:source]
    assert_equal expected_vars2, execs[1][:variables]
  end
end
