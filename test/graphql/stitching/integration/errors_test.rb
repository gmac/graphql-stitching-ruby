# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/errors"

describe 'GraphQL::Stitching, errors' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Errors::ElementsA,
      "b" => Schemas::Errors::ElementsB,
    })
  end

  def test_queries_merged_interfaces
    query = "
      query($ids: [ID!]!) {
        elementsA(ids: $ids) {
          name
          code
          discovery
        }
      }
    "

    result = plan_and_execute(@supergraph, query, {
      "ids" => ["10", "18", "36"]
    })

    pp result

    # @todo need assertions!
  end
end
