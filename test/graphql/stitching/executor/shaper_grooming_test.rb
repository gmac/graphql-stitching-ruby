# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Executor::Shaper, grooming" do
  def test_prunes_stitching_fields
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      %|{ test { __typename req opt } }|,
    )
    raw = {
      "test" => {
        "_export_req" => "yes",
        "_export___typename" => "Test",
        "__typename" => "Test",
        "req" => "yes",
        "opt" => nil,
      }
    }
    expected = {
      "test" => {
        "__typename" => "Test",
        "req" => "yes",
        "opt" => nil,
      }
    }

    assert_equal expected, GraphQL::Stitching::Executor::Shaper.new(request).perform!(raw)
  end

  def test_adds_missing_fields
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      "{ test { req opt } }",
    )
    raw = {
      "test" => {
        "_export_req" => "yes",
        "_export___typename" => "Test",
        "req" => "yes",
      }
    }
    expected = {
      "test" => {
        "req" => "yes",
        "opt" => nil,
      }
    }

    assert_equal expected, GraphQL::Stitching::Executor::Shaper.new(request).perform!(raw)
  end

  def test_grooms_through_inline_fragments
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    query = %|
      query {
        test {
          ... on Test {
            ... { req opt }
          }
        }
      }
    |
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      query,
    )
    raw = {
      "test" => {
        "_export_req" => "yes",
        "_export___typename" => "Test",
        "req" => "yes",
      }
    }
    expected = {
      "test" => {
        "req" => "yes",
        "opt" => nil,
      }
    }

    assert_equal expected, GraphQL::Stitching::Executor::Shaper.new(request).perform!(raw)
  end

  def test_grooms_through_fragment_spreads
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    query = %|
      query { test { ...Test2 } }
      fragment Test1 on Test { req opt }
      fragment Test2 on Test { ...Test1 }
    |
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      query,
    )
    raw = {
      "test" => {
        "_export_req" => "yes",
        "_export___typename" => "Test",
        "req" => "yes",
      }
    }
    expected = {
      "test" => {
        "req" => "yes",
        "opt" => nil,
      }
    }

    assert_equal expected, GraphQL::Stitching::Executor::Shaper.new(request).perform!(raw)
  end

  def test_grooms_returned_field_order_to_match_selection
    schema_sdl = %|
      type Shop {
        name: String
        currency: String
      }
      type Product {
        title: String
        price: Float
        parent: Product
      }
      type Query {
        products: [Product]!
        shop: Shop
      }
    |
    query = %|{
      products {
        title
        price
        parent {
          price
          title
        }
      }
      shop {
        name
        currency
      }
    }|
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      query,
    )
    raw = {
      "shop" => {
        "currency" => "USD",
        "name" => "Dog Haus",
      },
      "products" => [
        {
          "parent" => { "title" => "Leash set", "price" => 25.99 },
          "title" => "Collar",
          "price" => 7.99,
        },
        {
          "parent" => { "title" => "Bowl set", "price" => 19.99 },
          "title" => "Bowl",
          "price" => 5.99,
        },
      ],
    }

    expected = %|{"products":[{"title":"Collar","price":7.99,"parent":{"price":25.99,"title":"Leash set"}},{"title":"Bowl","price":5.99,"parent":{"price":19.99,"title":"Bowl set"}}],"shop":{"name":"Dog Haus","currency":"USD"}}|

    assert_equal expected, GraphQL::Stitching::Executor::Shaper.new(request).perform!(raw).to_json
  end

  def test_renames_root_query_typenames
    schema_sdl = "type Query { field: String }"
    source = %|
      fragment RootAttrs on Query { typename2: __typename }
      query {
        __typename
        ...on Query { typename1: __typename }
        ...RootAttrs
      }
    |
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      source,
    )

    raw = { "__typename" => "QueryRoot", "typename1" => "QueryRoot", "typename2" => "QueryRoot" }
    expected = { "__typename" => "Query", "typename1" => "Query", "typename2" => "Query" }
    assert_equal expected, GraphQL::Stitching::Executor::Shaper.new(request).perform!(raw)
  end

  def test_renames_root_mutation_typenames
    schema_sdl = "type Mutation { field: String } type Query { field: String }"
    source = %|
      fragment RootAttrs on Mutation { typename2: __typename }
      mutation {
        __typename
        ...on Mutation { typename1: __typename }
        ...RootAttrs
      }
    |
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema_sdl),
      source,
    )

    raw = { "__typename" => "MutationRoot", "typename1" => "MutationRoot", "typename2" => "MutationRoot" }
    expected = { "__typename" => "Mutation", "typename1" => "Mutation", "typename2" => "Mutation" }
    assert_equal expected, GraphQL::Stitching::Executor::Shaper.new(request).perform!(raw)
  end

  def test_handles_introspection_types
    schema_sdl = "type Test { req: String! opt: String } type Query { test: Test }"
    schema = GraphQL::Schema.from_definition(schema_sdl)
    request = GraphQL::Stitching::Request.new(
      supergraph_from_schema(schema),
      GraphQL::Introspection::INTROSPECTION_QUERY,
    )

    raw = schema.execute(GraphQL::Introspection::INTROSPECTION_QUERY).to_h
    assert GraphQL::Stitching::Executor::Shaper.new(request).perform!(raw)
  end
end
