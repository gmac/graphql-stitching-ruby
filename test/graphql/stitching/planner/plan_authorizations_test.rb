# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, authorizations" do
  def setup
    a = %|
      #{AUTHORIZATION_DEFINITION}
      type Customer @authorization(scopes: [["customers"]]) {
        email: String
      }
      type Order @authorization(scopes: [["orders"]]) {
        id: ID!
        shippingAddress: String!
        product: Product!
        customer1: Customer
        customer2: Customer @authorization(scopes: [["customers"]])
      }
      type Product @authorization(scopes: [["products"]]) {
        id: ID!
        price: Float!
      }
      type Query {
        orderA(id: ID!): Order @stitch(key: "id") @authorization(scopes: [["orders"]])
        productA(id: ID!): Product @stitch(key: "id")
      }
    |
    b = %|
      type Order {
        id: ID!
        open: String
      }
      type Product {
        id: ID!
        open: String
      }
      type Query {
        orderB(id: ID!): Order @stitch(key: "id")
        productB(id: ID!): Product @stitch(key: "id")
      }
    |

    @supergraph = compose_definitions({ "a"  =>  a, "b"  =>  b })
  end

  def test_selects_root_fields_without_authorization
    query = %|{
      productA(id: "1") {
        id
        price
      }
    }|

    plan = GraphQL::Stitching::Request.new(@supergraph, query).plan

    expected = {
      ops: [{
        step: 1,
        after: 0,
        location: "a",
        operation_type: "query",
        selections: %|{ productA(id: "1") { _export___typename: __typename } }|,
        variables: {},
        path: [],
      }],
      claims: [],
      errors: [
        { code: "unauthorized", path: ["productA", "id"] },
        { code: "unauthorized", path: ["productA", "price"] },
      ],
    }

    assert_equal expected, plan.as_json
  end

  def test_selects_root_fields_with_authorization
    query = %|{
      productA(id: "1") {
        id
        price
      }
    }|

    plan = GraphQL::Stitching::Request.new(@supergraph, query, claims: ["products"]).plan

    expected = {
      ops: [{
        step: 1,
        after: 0,
        location: "a",
        operation_type: "query",
        selections: %|{ productA(id: "1") { id price } }|,
        variables: {},
        path: [],
      }],
      claims: ["products"],
      errors: [],
    }

    assert_equal expected, plan.as_json
  end

  def test_selects_merged_object_fields_without_authorization
    query = %|{
      orderA(id: "1") {
        open
        product {
          id
          open
        }
      }
    }|

    plan = with_static_resolver_version do
      GraphQL::Stitching::Request.new(@supergraph, query, claims: ["orders"]).plan
    end

    expected = {
      ops: [{
        step: 1,
        after: 0,
        location: "a",
        operation_type: "query",
        selections: %|{ orderA(id: "1") { product { _export___typename: __typename _export_id: id } _export_id: id _export___typename: __typename } }|,
        variables: {},
        path: [],
      }, {
        step: 2,
        after: 1,
        location: "b",
        operation_type: "query",
        selections: %|{ open }|,
        variables: {},
        path: ["orderA", "product"],
        if_type: "Product",
        resolver: "b.productB.id.Product",
      }, {
        step: 3,
        after: 1,
        location: "b",
        operation_type: "query",
        selections: %|{ open }|,
        variables: {},
        path: ["orderA"],
        if_type: "Order",
        resolver: "b.orderB.id.Order",
      }],
      claims: ["orders"],
      errors: [
        { code: "unauthorized", path: ["orderA", "product", "id"] },
      ],
    }

    assert_equal expected, plan.as_json
  end

  def test_selects_merged_object_fields_with_authorization
    query = %|{
      orderA(id: "1") {
        open
        product {
          id
          open
        }
      }
    }|

    plan = with_static_resolver_version do
      GraphQL::Stitching::Request.new(@supergraph, query, claims: ["orders", "products"]).plan
    end
    
    expected = {
      ops: [{
        step: 1,
        after: 0,
        location: "a",
        operation_type: "query",
        selections: %|{ orderA(id: "1") { product { id _export_id: id _export___typename: __typename } _export_id: id _export___typename: __typename } }|,
        variables: {},
        path: [],
      }, {
        step: 2,
        after: 1,
        location: "b",
        operation_type: "query",
        selections: %|{ open }|,
        variables: {},
        path: ["orderA", "product"],
        if_type: "Product",
        resolver: "b.productB.id.Product",
      }, {
        step: 3,
        after: 1,
        location: "b",
        operation_type: "query",
        selections: %|{ open }|,
        variables: {},
        path: ["orderA"],
        if_type: "Order",
        resolver: "b.orderB.id.Order",
      }],
      claims: ["orders", "products"],
      errors: [],
    }

    assert_equal expected, plan.as_json
  end

  def test_selects_unmerged_object_fields_without_authorization
    query = %|{
      orderA(id: "1") {
        customer1 { email }
        customer2 { email }
      }
    }|

    plan = with_static_resolver_version do
      GraphQL::Stitching::Request.new(@supergraph, query, claims: ["orders"]).plan
    end

    expected = {
      ops: [{
        step: 1,
        after: 0,
        location: "a",
        operation_type: "query",
        selections: %|{ orderA(id: "1") { customer1 { _export___typename: __typename } _export___typename: __typename } }|,
        variables: {},
        path: [],
      }],
      claims: ["orders"],
      errors: [
        { code: "unauthorized", path: ["orderA", "customer1", "email"] },
        { code: "unauthorized", path: ["orderA", "customer2"] },
      ],
    }

    assert_equal expected, plan.as_json
  end

  def test_selects_unmerged_object_fields_with_authorization
    query = %|{
      orderA(id: "1") {
        customer1 { email }
        customer2 { email }
      }
    }|

    plan = with_static_resolver_version do
      GraphQL::Stitching::Request.new(@supergraph, query, claims: ["orders", "customers"]).plan
    end
    
    expected = {
      ops: [{
        step: 1,
        after: 0,
        location: "a",
        operation_type: "query",
        selections: %|{ orderA(id: "1") { customer1 { email } customer2 { email } } }|,
        variables: {},
        path: [],
      }],
      claims: ["orders", "customers"],
      errors: [],
    }

    assert_equal expected, plan.as_json
  end
end
