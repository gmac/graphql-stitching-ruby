# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/authorizations"

describe 'GraphQL::Stitching, authorizations' do
  def setup
    @supergraph = compose_definitions({
      "alpha" => Schemas::Authorizations::Alpha,
      "bravo" => Schemas::Authorizations::Bravo,
    })
  end

  def test_responds_with_error
    query = %|{
      orderA(id: "1") {
        customer1 {
          phone
        }
      }
    }|

    result = plan_and_execute(@supergraph, query, claims: ["orders"]) do |plan|
      pp plan.as_json
    end

    pp result.to_h
    assert true
  end
end
