# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/unions"

describe 'GraphQL::Stitching, unions' do
  def setup
    @supergraph = compose_definitions({
      "a" => TestSchema::Unions::SchemaA,
      "b" => TestSchema::Unions::SchemaB,
      "c" => TestSchema::Unions::SchemaC,
    })
  end

  def test_plan_abstract_merged_via_concrete_boundaries
    query = "{
      fruitsA(ids: [\"1\", \"3\"]) {
        ...on Apple { a b c }
        ...on Banana { a b }
        ...on Coconut { b c }
      }
    }"

    result = plan_and_execute(@supergraph, query)

    # pp plan.to_h
    pp result
  end

  def test_plan_abstract_merged_types_via_abstract_boundary
    query = "{
      fruitsC(ids: [\"1\", \"4\"]) {
        ...on Apple { a b c }
        ...on Banana { a b }
        ...on Coconut { b c }
      }
    }"

    result = plan_and_execute(@supergraph, query)

    # pp plan.to_h
    pp result
  end
end
