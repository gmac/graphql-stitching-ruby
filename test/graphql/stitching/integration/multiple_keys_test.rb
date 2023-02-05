# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/multiple_keys"

describe 'GraphQL::Stitching, multiple keys' do
  def setup
    @supergraph = compose_definitions({
      "storefronts" => Schemas::MultipleKeys::Storefronts,
      "products" => Schemas::MultipleKeys::Products,
      "catelogs" => Schemas::MultipleKeys::Catelogs,
    })
  end

  def test_queries_through_multiple_keys_from_outer_edge
    # @todo fails when resolved via GraphQL due to alias...

    # result = plan_and_execute(@supergraph, "{ result: storefrontsProductById(id: \"1\") { location edition } }")

    # assert_equal "Toronto", result.dig("data", "result", "location")
    # assert_equal "Spring", result.dig("data", "result", "edition")
  end

  def test_queries_through_multiple_keys_from_center
    # @todo fails when resolved via GraphQL due to alias...

    # result = plan_and_execute(@supergraph, "{ result: productsProductById(id: \"1\") { location edition } }")

    # assert_equal "Toronto", result.dig("data", "result", "location")
    # assert_equal "Spring", result.dig("data", "result", "edition")
  end
end
