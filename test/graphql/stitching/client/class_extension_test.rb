# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"

describe "GraphQL::Stitching::Client" do
  class MyClient < GraphQL::Stitching::Client
    def merge_descriptions(values_by_location, _info)
      values_by_location.values.join("/")
    end

    def build_graphql_error(request, err)
      { "message" => "Contact support about request #{request.context[:request_id]}." }
    end
  end

  def test_client_acts_as_composition_formatter
    alpha = %|
      """
      a
      """
      type Query { a:Boolean }
    |
    bravo = %|
      """
      b
      """
      type Query { b:Boolean }
    |

    client = MyClient.new(locations: {
      "alpha" => { schema: GraphQL::Schema.from_definition(alpha) },
      "bravo" => { schema: GraphQL::Schema.from_definition(bravo) },
    })
    
    assert_equal "a/b", client.supergraph.schema.query.description
  end

  def test_client_builds_graphql_errors
    client = MyClient.new(locations: {
      products: { schema: Schemas::Example::Products },
    })

    result = client.execute(
      query: "query { invalidSelection }",
      context: { request_id: "R2d2c3P0" },
      validate: false
    )

    expected_errors = [{
      "message" => "Contact support about request R2d2c3P0.",
    }]

    assert_nil result["data"]
    assert_equal expected_errors, result["errors"]
  end

  def test_client_from_definition_builds_specific_class
    alpha = %|
      type T { id:ID! a:String }
      type Query { a(id:ID!):T @stitch(key: "id") }
    |
    bravo = %|
      type T { id:ID! b:String }
      type Query { b(id:ID!):T @stitch(key: "id") }
    |

    sdl = compose_definitions({ "alpha" => alpha, "bravo" => bravo }).to_definition
    client = MyClient.from_definition(sdl, executables: {
      "alpha" => Proc.new {},
      "bravo" => Proc.new {},
    })
    assert client.is_a?(MyClient)
  end
end