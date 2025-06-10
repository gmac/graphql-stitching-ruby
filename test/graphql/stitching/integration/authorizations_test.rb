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

  def test_errors_unauthorized_root_field_selections
    query = %|{
      a1: orderA(id: "1") { shippingAddress }
      a2: productA(id: "1") { name }
      ...on Query {
        b1: orderA(id: "1") { shippingAddress }
        b2: productA(id: "1") { description }
        ... QueryAttrs
      }
    }
    fragment QueryAttrs on Query {
      c1: orderA(id: "1") { shippingAddress }
      c2: productA(id: "1") { price }
    }|

    result = plan_and_execute(@supergraph, query)
    expected = {
      "data" => { 
        "a1" => nil,
        "a2" => nil,
        "b1" => nil,
        "b2" => { "description" => nil },
        "c1" => nil,
        "c2" => nil,
      },
      "errors" => [{
        "message" => "Unauthorized access",
        "path" => ["a1"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["b1"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["c1"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["a2", "name"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["b2", "description"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["c2", "price"],
        "extensions" => { "code" => "unauthorized" },
      }],
    }

    assert_equal expected, result.to_h
  end

  def test_stitches_around_unauthorized_access
    query = %|{
      orderA(id: "1") {
        open
        customer1 {
          email
        }
        customer2 {
          email
        }
        product {
          description
          open
        }
      }
    }|

    result = plan_and_execute(@supergraph, query, claims: ["orders"])
    expected = {
      "data" => { 
        "orderA" => {
          "open" => true,
          "customer1" => nil,
          "customer2" => nil,
          "product" => {
            "description" => nil,
            "open" => true,
          }
        }
      },
      "errors" => [{
        "message" => "Unauthorized access",
        "path" => ["orderA", "customer1", "email"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["orderA", "customer2"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["orderA", "product", "description"],
        "extensions" => { "code" => "unauthorized" },
      }],
    }

    assert_equal expected, result.to_h
  end

  def test_stitches_around_unauthorized_access_from_opposing_entrypoint
    query = %|{
      orderB(id: "1") {
        open
        customer1 {
          email
        }
        customer2 {
          email
        }
        product {
          description
          open
        }
      }
    }|

    result = plan_and_execute(@supergraph, query, claims: ["orders"])
    expected = {
      "data" => { 
        "orderB" => {
          "open" => true,
          "customer1" => nil,
          "customer2" => nil,
          "product" => {
            "description" => nil,
            "open" => true,
          }
        }
      },
      "errors" => [{
        "message" => "Unauthorized access",
        "path" => ["orderB", "customer2"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["orderB", "customer1", "email"],
        "extensions" => { "code" => "unauthorized" },
      }, {
        "message" => "Unauthorized access",
        "path" => ["orderB", "product", "description"],
        "extensions" => { "code" => "unauthorized" },
      }],
    }

    assert_equal expected, result.to_h
  end
end
