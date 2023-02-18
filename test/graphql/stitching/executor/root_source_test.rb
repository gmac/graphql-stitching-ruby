# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Executor, RootSource" do
  def setup
    @op = {
      "key"=>1,
      "after_key"=>0,
      "location"=>"products",
      "operation_type"=>"query",
      "insertion_path"=>[],
      "type_condition"=>"Storefront",
      "selections"=>"{ storefront(id:$id) { products { _STITCH_id: id } } }",
      "variables"=>{ "id" => "ID!" },
      "boundary"=>nil
    }

    @source = GraphQL::Stitching::Executor::RootSource.new({}, "a")
  end

  def test_builds_document_for_an_operation
    source_document = @source.build_document(@op)

    expected = <<~GRAPHQL
      query($id:ID!){
        storefront(id:$id) { products { _STITCH_id: id } }
      }
    GRAPHQL

    assert_equal squish_string(expected), source_document
  end

  def test_builds_document_with_operation_name
    source_document = @source.build_document(@op, "MyOperation")

    expected = <<~GRAPHQL
      query MyOperation_1($id:ID!){
        storefront(id:$id) { products { _STITCH_id: id } }
      }
    GRAPHQL

    assert_equal squish_string(expected), source_document
  end
end
