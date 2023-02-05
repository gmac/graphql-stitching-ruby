# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/conditionals"

describe 'GraphQL::Stitching, type conditions' do
  def setup
    @supergraph = compose_definitions({
      "ext" => Schemas::Conditionals::Extensions,
      "base" => Schemas::Conditionals::Abstracts,
    })
  end

  def test_queries_merged_interfaces
    query = "
      query($ids: [ID!]!) {
        fruits(ids: $ids) {
          ...on Apple { extensions { color } }
          ...on Banana { extensions { shape } }
        }
      }
    "

    _result = plan_and_execute(@supergraph, query, {
      "ids" => ["1"]
    })

    # pp _result

    # @todo need assertions!
  end
end
