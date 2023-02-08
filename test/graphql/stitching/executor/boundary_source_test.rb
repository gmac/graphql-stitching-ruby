# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Executor, BoundarySource" do
  def setup
    @op1 = {
      "key"=>2,
      "after_key"=>1,
      "location"=>"products",
      "operation_type"=>"query",
      "insertion_path"=>["storefronts"],
      "type_condition"=>"Storefront",
      "selections"=>"{ name(lang:$lang) }",
      "variables"=>{ "lang" => "String!" },
      "boundary"=>{
        "location"=>"products",
        "selection"=>"id",
        "field"=>"storefronts",
        "arg"=>"ids",
        "list"=>true,
        "type_name"=>"Storefront"
      }
    }
    @op2 = {
      "key"=>3,
      "after_key"=>1,
      "location"=>"products",
      "operation_type"=>"query",
      "insertion_path"=>["storefronts", "product"],
      "type_condition"=>"Product",
      "selections"=>"{ price(currency:$currency) }",
      "variables"=>{ "currency" => "Currency!" },
      "boundary"=>{
        "location"=>"products",
        "selection"=>"upc",
        "field"=>"product",
        "arg"=>"upc",
        "list"=>false,
        "type_name"=>"Product"
      }
    }

    @source = GraphQL::Stitching::Executor::BoundarySource.new({}, "products")
    @origin_sets_by_operation = {
      @op1 => [{ "_STITCH_id" => "7" }, { "_STITCH_id" => "8" }],
      @op2 => [{ "_STITCH_upc" => "abc" }, { "_STITCH_upc" => "xyz" }],
    }
  end

  def test_builds_query_for_operation_batch
    query_document, variable_names = @source.build_query(@origin_sets_by_operation)

    expected = <<~GRAPHQL
      query($lang:String!,$currency:Currency!){
        _0_result: storefronts(ids:["7","8"]) { name(lang:$lang) }
        _1_0_result: product(upc:"abc") { price(currency:$currency) }
        _1_1_result: product(upc:"xyz") { price(currency:$currency) }
      }
    GRAPHQL

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
      { "_STITCH_id" => "7", "name" => "fizz" },
      { "_STITCH_id" => "8", "name" => "bang" }
    ]
    expected2 = [
      { "_STITCH_upc" => "abc", "price" => 1.99 },
      { "_STITCH_upc" => "xyz", "price" => 10.99 }
    ]

    assert_equal expected1, @origin_sets_by_operation[@op1]
    assert_equal expected2, @origin_sets_by_operation[@op2]
  end

  def test_extracts_errors_for_operation_batch
    data = {
      "storefronts" => [
        { "_STITCH_id" => "7", "product" => { "_STITCH_upc" => "abc" } },
        { "_STITCH_id" => "8", "product" => { "_STITCH_upc" => "xyz" } }
      ]
    }

    mock = GraphQL::Stitching::Executor.new(supergraph: {}, plan: { "ops" => [] })
    mock.instance_variable_set(:@data, data)

    @source = GraphQL::Stitching::Executor::BoundarySource.new(mock, "products")
    @origin_sets_by_operation = {
      @op1 => data["storefronts"],
      @op2 => data["storefronts"].map { _1["product"] },
    }

    result = @source.extract_errors!(@origin_sets_by_operation, [
      { "path" => [], "message" => "base error" },
      { "path" => ["_0_result", 1], "message" => "list error" },
      { "path" => ["_1_1_result"], "message" => "itemized error" },
    ])

    expected = [
      { "path" => [], "message" => "base error" },
      { "path" => ["storefronts", 1], "message" => "list error" },
      { "path" => ["storefronts", 1, "product"], "message" => "itemized error" },
    ]

    assert_equal expected, result
  end
end
