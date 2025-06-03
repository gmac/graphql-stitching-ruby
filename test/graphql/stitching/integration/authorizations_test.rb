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

  def test_responds_with_errors_for_each_unauthorized_child_field
    query = %|{
      orderA(id: "1") {
        customer1 {
          phone
          slack
        }
      }
    }|

    result = plan_and_execute(@supergraph, query, claims: ["orders"])
    expected = {
      "data" => { 
        "orderA" => { 
          "customer1" => {
            "phone" => nil,
            "slack" => nil,
          },
        },
      },
      "errors" => [{
        "message" => "Unauthorized access",
        "path" => ["orderA", "customer1", "phone"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["orderA", "customer1", "slack"],
        "extensions" => { "code" => "unauthorized" },
      }],
    }

    assert_equal expected, result.to_h
  end

  def test_errors_of_non_null_child_fields_bubble
    query = %|{
      orderA(id: "1") {
        customer1 {
          email
        }
      }
    }|

    result = plan_and_execute(@supergraph, query, claims: ["orders"])
    expected = {
      "data" => { 
        "orderA" => { "customer1" => nil },
      },
      "errors" => [{
        "message" => "Unauthorized access",
        "path" => ["orderA", "customer1", "email"],
        "extensions" => { "code" => "unauthorized" },
      }],
    }

    assert_equal expected, result.to_h
  end

  def test_responds_with_error_for_unauthorized_parent_field
    query = %|{
      orderA(id: "1") {
        customer2 {
          phone
        }
      }
    }|

    result = plan_and_execute(@supergraph, query, claims: ["orders"])
    expected = {
      "data" => { 
        "orderA" => { "customer2" => nil },
      },
      "errors" => [{
        "message" => "Unauthorized access",
        "path" => ["orderA", "customer2"],
        "extensions" => { "code" => "unauthorized" },
      }],
    }

    assert_equal expected, result.to_h
  end

  def test_expected_results_with_proper_permissions
    query = %|{
      orderA(id: "1") {
        customer2 {
          email
          phone
          slack
        }
      }
    }|

    result = plan_and_execute(@supergraph, query, claims: ["orders", "customers"])
    expected = {
      "data" => { 
        "orderA" => { 
          "customer2" => {
            "email" => "pete.cat@gmail.com",
            "phone" => "123.456.7890",
            "slack" => nil,
          }, 
        },
      },
    }

    assert_equal expected, result.to_h
  end
end
