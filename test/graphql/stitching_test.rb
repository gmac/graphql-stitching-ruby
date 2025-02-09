# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching" do
  def test_digest_gets_and_sets_hashing_implementation
    expected_sha = "f5a163f364ac65dfd8ef60edb3ba39d6c2b44bccc289af3ced96b06e3f25df59"
    expected_md5 = "fec9ff7a551c37ef692994407710fa54"

    GraphQL::Stitching.stub_const(:VERSION, "1.5.1") do
      fn = GraphQL::Stitching.digest
      assert_equal expected_sha, new_type_resolver.version

      GraphQL::Stitching.digest { |str| Digest::MD5.hexdigest(str) }
      assert_equal expected_md5, new_type_resolver.version

      GraphQL::Stitching.digest(&fn)
      assert_equal expected_sha, new_type_resolver.version
    end
  end

  private

  def new_type_resolver
    GraphQL::Stitching::TypeResolver.new(
      location: "a",
      type_name: "Test",
      list: false,
      field: "a",
      key: GraphQL::Stitching::TypeResolver.parse_key("id"),
      arguments: GraphQL::Stitching::TypeResolver.parse_arguments_with_type_defs("id: $.id", "id: ID"),
    )
  end
end
