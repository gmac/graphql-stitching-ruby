# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Executor, TypeResolverSource" do
  def setup
    @resolver1 = GraphQL::Stitching::TypeResolver.new(
      location: "products",
      type_name: "Storefront",
      list: true,
      field: "storefronts",
      key: GraphQL::Stitching::TypeResolver.parse_key("id"),
      arguments: GraphQL::Stitching::TypeResolver.parse_arguments_with_type_defs("ids: $.id", "ids: [ID]"),
    )
    @resolver2 = GraphQL::Stitching::TypeResolver.new(
      location: "products",
      type_name: "Product",
      list: false,
      field: "product",
      key: GraphQL::Stitching::TypeResolver.parse_key("upc"),
      arguments: GraphQL::Stitching::TypeResolver.parse_arguments_with_type_defs("upc: $.upc", "upc: ID"),
    )

    @op1 = GraphQL::Stitching::Plan::Op.new(
      step: 2,
      after: 1,
      location: "products",
      operation_type: "query",
      path: ["storefronts"],
      if_type: "Storefront",
      selections: "{ name(lang:$lang) }",
      variables: { "lang" => "String!" },
      resolver: @resolver1.version,
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
      resolver: @resolver2.version,
    )
    
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Class.new(GraphQL::Schema), 
      resolvers: {
        "Storefront" => [@resolver1],
        "Product" => [@resolver2],
      }
    )
    request = GraphQL::Stitching::Request.new(supergraph, "{ test }")
    executor = GraphQL::Stitching::Executor.new(request)
    @source = GraphQL::Stitching::Executor::TypeResolverSource.new(executor, "products")
    @origin_sets_by_operation = {
      @op1 => [{ "_export_id" => "7" }, { "_export_id" => "8" }],
      @op2 => [{ "_export_upc" => "abc" }, { "_export_upc" => "xyz" }],
    }
  end

  def test_builds_document_for_operation_batch
    query_document, variable_names = @source.build_document(@origin_sets_by_operation)

    expected = %|
      query($lang:String!,$_0_key_0:[ID!]!,$currency:Currency!,$_1_0_key_0:ID!,$_1_1_key_0:ID!){
        _0_result: storefronts(ids:$_0_key_0) { name(lang:$lang) }
        _1_0_result: product(upc:$_1_0_key_0) { price(currency:$currency) }
        _1_1_result: product(upc:$_1_1_key_0) { price(currency:$currency) }
      }
    |

    assert_equal squish_string(expected), query_document
    assert_equal ["lang", "currency"], variable_names
  end

  def test_builds_document_with_operation_name
    query_document, variable_names = @source.build_document(@origin_sets_by_operation, "MyOperation")

    expected = %|
      query MyOperation_2_3($lang:String!,$_0_key_0:[ID!]!,$currency:Currency!,$_1_0_key_0:ID!,$_1_1_key_0:ID!){
        _0_result: storefronts(ids:$_0_key_0) { name(lang:$lang) }
        _1_0_result: product(upc:$_1_0_key_0) { price(currency:$currency) }
        _1_1_result: product(upc:$_1_1_key_0) { price(currency:$currency) }
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
      query MyOperation_2_3($lang:String!,$_0_key_0:[ID!]!,$currency:Currency!,$_1_0_key_0:ID!,$_1_1_key_0:ID!) @inContext(lang: "EN") {
        _0_result: storefronts(ids:$_0_key_0) { name(lang:$lang) }
        _1_0_result: product(upc:$_1_0_key_0) { price(currency:$currency) }
        _1_1_result: product(upc:$_1_1_key_0) { price(currency:$currency) }
      }
    |

    assert_equal squish_string(expected), query_document
    assert_equal ["lang", "currency"], variable_names
  end

  def test_generated_variables_do_not_leak_between_documents
    query_document, variable_names, generated_variables = @source.build_document({
      @op1 => [{ "_export_id" => "7" }, { "_export_id" => "8" }],
    })

    expected_source = %|
      query($lang:String!,$_0_key_0:[ID!]!){
        _0_result: storefronts(ids:$_0_key_0) { name(lang:$lang) }
      }
    |

    assert_equal squish_string(expected_source), query_document
    assert_equal ["lang"], variable_names
    assert_equal({ "_0_key_0" => ["7", "8"] }, generated_variables)

    query_document, variable_names, generated_variables = @source.build_document({
      @op2 => [{ "_export_upc" => "abc" }],
    })

    expected_source = %|
      query($currency:Currency!,$_0_0_key_0:ID!){
        _0_0_result: product(upc:$_0_0_key_0) { price(currency:$currency) }
      }
    |

    assert_equal squish_string(expected_source), query_document
    assert_equal ["currency"], variable_names
    assert_equal({ "_0_0_key_0" => "abc" }, generated_variables)
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

  def test_extracts_pathed_errors_with_null_siblings
    data = {
      "storefronts" => [
        nil,
        { "_export_id" => "8", "product" => { "_export_upc" => "xyz" } },
      ]
    }

    with_mock_source(data) do |source, _origin_sets_by_operation|
      result = source.extract_errors!({
        @op2 => [data["storefronts"][1]["product"]],
      }, [
        { "path" => ["_0_0_result"], "message" => "itemized error" },
      ])

      expected = [
        { "path" => ["storefronts", 1, "product"], "message" => "itemized error" },
      ]

      assert_equal expected, result
    end
  end

  def test_builds_document_from_nested_list_origin_paths
    op = GraphQL::Stitching::Plan::Op.new(
      step: 4,
      after: 1,
      location: "products",
      operation_type: "query",
      path: ["storefronts"],
      selections: "{ price(currency:$currency) }",
      variables: { "currency" => "Currency!" },
      resolver: @resolver2.version,
    )

    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Class.new(GraphQL::Schema),
      resolvers: {
        "Product" => [@resolver2],
      },
      executables: {
        "products" => -> (_request, _source, _variables) {
          {
            "data" => {
              "_0_0_result" => { "price" => 1.99 },
              "_0_1_result" => { "price" => 10.99 },
            },
          }
        },
      },
    )
    request = GraphQL::Stitching::Request.new(supergraph, "{ test }")
    executor = GraphQL::Stitching::Executor.new(request)
    executor.data.merge!(
      "storefronts" => [
        [{ "_export_upc" => "abc" }],
        nil,
        [{ "_export_upc" => "xyz" }],
      ],
    )

    source = GraphQL::Stitching::Executor::TypeResolverSource.new(executor, "products")
    source.fetch([op])

    assert_equal 1.99, executor.data.dig("storefronts", 0, 0, "price")
    assert_equal 10.99, executor.data.dig("storefronts", 2, 0, "price")
  end

  private

  def with_mock_source(data = nil)
    data ||= {
      "storefronts" => [
        { "_export_id" => "7", "product" => { "_export_upc" => "abc" } },
        { "_export_id" => "8", "product" => { "_export_upc" => "xyz" } }
      ]
    }

    sg = GraphQL::Stitching::Supergraph.new(schema: Class.new(GraphQL::Schema))
    mock = GraphQL::Stitching::Request.new(sg, "{}")
    mock.plan(GraphQL::Stitching::Plan.new(ops: []))

    mock = GraphQL::Stitching::Executor.new(mock)
    mock.instance_variable_set(:@data, data)

    source = GraphQL::Stitching::Executor::TypeResolverSource.new(mock, "products")
    origin_sets_by_operation = {
      @op1 => data["storefronts"].compact,
      @op2 => data["storefronts"].filter_map { _1 && _1["product"] },
    }

    yield(source, origin_sets_by_operation)
  end
end
