# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Executor, RootSource" do
  def setup
    @op = GraphQL::Stitching::Plan::Op.new(
      step: 1,
      after: 0,
      location: "products",
      operation_type: "query",
      path: [],
      if_type: "Storefront",
      selections: "{ storefront(id:$id) { products { _export_id: id } } }",
      variables: { "id" => "ID!" },
      resolver: nil
    )

    @source = GraphQL::Stitching::Executor::RootSource.new({}, "a")
  end

  def test_builds_document_for_an_operation
    source_document = @source.build_document(@op)

    expected = %|
      query($id:ID!){
        storefront(id:$id) { products { _export_id: id } }
      }
    |

    assert_equal squish_string(expected), source_document
  end

  def test_builds_document_with_operation_name
    source_document = @source.build_document(@op, "MyOperation")

    expected = %|
      query MyOperation_1($id:ID!){
        storefront(id:$id) { products { _export_id: id } }
      }
    |

    assert_equal squish_string(expected), source_document
  end

  def test_builds_document_with_operation_directives
    source_document = @source.build_document(@op, "MyOperation", %|@inContext(lang: "EN")|)

    expected = %|
      query MyOperation_1($id:ID!) @inContext(lang: "EN") {
        storefront(id:$id) { products { _export_id: id } }
      }
    |

    assert_equal squish_string(expected), source_document
  end

  def test_fetches_all_batched_root_operations
    op1 = GraphQL::Stitching::Plan::Op.new(
      step: 2,
      after: 1,
      location: "products",
      operation_type: "query",
      path: ["nodeA"],
      selections: "{ title }",
      variables: {},
      resolver: nil,
    )
    op2 = GraphQL::Stitching::Plan::Op.new(
      step: 3,
      after: 1,
      location: "products",
      operation_type: "query",
      path: ["nodeB", "nested"],
      selections: "{ price }",
      variables: {},
      resolver: nil,
    )

    executor, calls = executor_with_root_results([
      { "title" => "Hat" },
      { "price" => 19.99 },
    ])
    executor.data.merge!(
      "nodeA" => {},
      "nodeB" => { "nested" => {} },
    )

    source = GraphQL::Stitching::Executor::RootSource.new(executor, "products")
    result = source.fetch([op1, op2])

    assert_equal [2, 3], result
    assert_equal 2, calls.length
    assert_equal({ "title" => "Hat" }, executor.data["nodeA"])
    assert_equal({ "price" => 19.99 }, executor.data.dig("nodeB", "nested"))
  end

  def test_repaths_nested_root_errors_for_each_list_element
    op = GraphQL::Stitching::Plan::Op.new(
      step: 2,
      after: 1,
      location: "products",
      operation_type: "query",
      path: ["items", "query"],
      selections: "{ errorB }",
      variables: {},
      resolver: nil,
    )

    executor, = executor_with_root_results([
      { "errors" => [{ "message" => "b", "path" => ["errorB"], "locations" => [{ "line" => 1 }] }] },
    ])
    executor.data.merge!(
      "items" => [
        { "query" => {} },
        nil,
        { "query" => {} },
      ],
    )

    source = GraphQL::Stitching::Executor::RootSource.new(executor, "products")
    result = source.fetch([op])

    expected_errors = [
      { "message" => "b", "path" => ["items", 0, "query", "errorB"] },
      { "message" => "b", "path" => ["items", 2, "query", "errorB"] },
    ]

    assert_equal [2], result
    assert_equal expected_errors, executor.errors
  end

  private

  def executor_with_root_results(results)
    calls = []
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Class.new(GraphQL::Schema),
      executables: {
        "products" => -> (_request, source, variables) {
          calls << { source: source, variables: variables }
          result = results.shift
          result.key?("data") || result.key?("errors") ? result : { "data" => result }
        },
      },
    )
    request = GraphQL::Stitching::Request.new(supergraph, "{}")
    executor = GraphQL::Stitching::Executor.new(request)

    [executor, calls]
  end
end
