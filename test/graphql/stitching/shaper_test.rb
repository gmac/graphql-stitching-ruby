# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/errors"

describe 'GraphQL::Stitching::Shaper' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Errors::ElementsA,
      "b" => Schemas::Errors::ElementsB,
    })
  end

  def test_shapes_a_request
    query = "
      query($ids: [ID!]!) {
        elementsA(ids: $ids) {
          name
          code
          year
        }
      }
    "

    document = GraphQL::Stitching::Document.new(query)

    plan = GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      document: document,
    ).perform

    executor = GraphQL::Stitching::Executor.new(
      supergraph: @supergraph,
      plan: plan.to_h,
      variables: { "ids" => ["10", "18", "36"] },
    )

    result = executor.perform(document)

    pp GraphQL::Stitching::Shaper.perform(@supergraph.schema, document, result)
  end
end
