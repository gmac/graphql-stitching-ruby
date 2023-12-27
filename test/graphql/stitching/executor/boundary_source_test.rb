# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Executor, BoundarySource" do
  def setup
    @op1 = GraphQL::Stitching::Plan::Op.new(
      step: 2,
      after: 1,
      location: "products",
      operation_type: "query",
      path: ["storefronts"],
      if_type: "Storefront",
      selections: "{ name(lang:$lang) }",
      variables: { "lang" => "String!" },
      boundary: GraphQL::Stitching::Boundary.new(
        location: "products",
        field: "storefronts",
        arg: "ids",
        key: "id",
        list: true,
        type_name: "Storefront"
      )
    )
    @op2 = GraphQL::Stitching::Plan::Op.new(
      step: 3,
      after: 1,
      location: "products",
      operation_type: "query",
      path: ["storefronts", "product"],
      if_type: "Product",
      selections: "{ price(currency:$currency) }",
      variables: { "currency" => "Currency!" },
      boundary: GraphQL::Stitching::Boundary.new(
        location: "products",
        field: "product",
        arg: "upc",
        key: "upc",
        list: false,
        type_name: "Product"
      )
    )

    @source = GraphQL::Stitching::Executor::BoundarySource.new({}, "products")
    @origin_sets_by_operation = {
      @op1 => [{ "_export_id" => "7" }, { "_export_id" => "8" }],
      @op2 => [{ "_export_upc" => "abc" }, { "_export_upc" => "xyz" }],
    }
  end

  def test_builds_document_for_operation_batch
    query_document, variable_names = @source.build_document(@origin_sets_by_operation)

    expected = %|
      query($lang:String!,$currency:Currency!){
        _0_result: storefronts(ids:["7","8"]) { name(lang:$lang) }
        _1_0_result: product(upc:"abc") { price(currency:$currency) }
        _1_1_result: product(upc:"xyz") { price(currency:$currency) }
      }
    |

    assert_equal squish_string(expected), query_document
    assert_equal ["lang", "currency"], variable_names
  end

  def test_builds_document_with_operation_name
    query_document, variable_names = @source.build_document(@origin_sets_by_operation, "MyOperation")

    expected = %|
      query MyOperation_2_3($lang:String!,$currency:Currency!){
        _0_result: storefronts(ids:["7","8"]) { name(lang:$lang) }
        _1_0_result: product(upc:"abc") { price(currency:$currency) }
        _1_1_result: product(upc:"xyz") { price(currency:$currency) }
      }
    |

    assert_equal squish_string(expected), query_document
    assert_equal ["lang", "currency"], variable_names
  end

  def test_builds_document_with_operation_directives
    query_document, variable_names = @source.build_document(
      @origin_sets_by_operation,
      "MyOperation",
      %|@inContext(lang: "EN")|,
    )

    expected = %|
      query MyOperation_2_3($lang:String!,$currency:Currency!) @inContext(lang: "EN") {
        _0_result: storefronts(ids:["7","8"]) { name(lang:$lang) }
        _1_0_result: product(upc:"abc") { price(currency:$currency) }
        _1_1_result: product(upc:"xyz") { price(currency:$currency) }
      }
    |

    assert_equal squish_string(expected), query_document
    assert_equal ["lang", "currency"], variable_names
  end

  def test_merges_results_for_operation_batch
    @source.merge_results!(@origin_sets_by_operation, {
      "_0_result" => [{ "name" => "fizz" }, { "name" => "bang" }],
      "_1_0_result" => { "price" => 1.99 },
      "_1_1_result" => { "price" => 10.99 },
    })

    expected1 = [
      { "_export_id" => "7", "name" => "fizz" },
      { "_export_id" => "8", "name" => "bang" }
    ]
    expected2 = [
      { "_export_upc" => "abc", "price" => 1.99 },
      { "_export_upc" => "xyz", "price" => 10.99 }
    ]

    assert_equal expected1, @origin_sets_by_operation[@op1]
    assert_equal expected2, @origin_sets_by_operation[@op2]
  end

  def test_extracts_base_error_for_operation_batch
    with_mock_source do |source, origin_sets_by_operation|
      result = source.extract_errors!(origin_sets_by_operation, [
        { "path" => [], "message" => "base error" },
      ])

      expected = [
        { "path" => [], "message" => "base error" },
      ]

      assert_equal expected, result
    end
  end

  def test_extracts_pathed_errors_for_operation_batch
    with_mock_source do |source, origin_sets_by_operation|
      result = source.extract_errors!(origin_sets_by_operation, [
        { "path" => ["_0_result", 1], "message" => "list error" },
        { "path" => ["_1_1_result"], "message" => "itemized error" },
      ])

      expected = [
        { "path" => ["storefronts", 1], "message" => "list error" },
        { "path" => ["storefronts", 1, "product"], "message" => "itemized error" },
      ]

      assert_equal expected, result
    end
  end

  private

  def with_mock_source
    data = {
      "storefronts" => [
        { "_export_id" => "7", "product" => { "_export_upc" => "abc" } },
        { "_export_id" => "8", "product" => { "_export_upc" => "xyz" } }
      ]
    }

    mock = GraphQL::Stitching::Request.new({}, "{}")
    mock.plan(GraphQL::Stitching::Plan.new(ops: []))

    mock = GraphQL::Stitching::Executor.new(mock)
    mock.instance_variable_set(:@data, data)

    source = GraphQL::Stitching::Executor::BoundarySource.new(mock, "products")
    origin_sets_by_operation = {
      @op1 => data["storefronts"],
      @op2 => data["storefronts"].map { _1["product"] },
    }

    yield(source, origin_sets_by_operation)
  end
end
