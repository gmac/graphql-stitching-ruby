# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::Compose::MergeRootObjectsTest < Minitest::Test

  ComposeError = GraphQL::Stitching::Compose::ComposeError

  def test_merges_fields_of_root_scopes
    a = "type Query { a:String } type Mutation { a:String }"
    b = "type Query { b:String } type Mutation { b:String }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["a","b"], schema.types["Query"].fields.keys.sort
    assert_equal ["a","b"], schema.types["Mutation"].fields.keys.sort
  end

  def test_merges_fields_of_root_scopes_from_custom_names
    a = "type RootQ { a:String } type RootM { a:String } schema { query:RootQ mutation:RootM }"
    b = "type Query { b:String } type Mutation { b:String }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["a","b"], schema.types["Query"].fields.keys.sort
    assert_equal ["a","b"], schema.types["Mutation"].fields.keys.sort
  end

  def test_merges_fields_of_root_scopes_into_custom_names
    a = "type Query { a:String } type Mutation { a:String }"
    b = "type Query { b:String } type Mutation { b:String }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b }, {
      query_name: "RootQuery",
      mutation_name: "RootMutation",
    })

    assert_equal ["a","b"], schema.types["RootQuery"].fields.keys.sort
    assert_equal ["a","b"], schema.types["RootMutation"].fields.keys.sort
    assert_nil schema.get_type("Query")
    assert_nil schema.get_type("Mutation")
  end

  def test_errors_for_subscription
    a = "type Query { a:String } type Mutation { a:String } type Subscription { b:String }"

    assert_error('subscription operation is not supported', ComposeError) do
      compose_definitions({ "a" => a })
    end
  end

  def test_errors_for_query_type_name_conflict
    a = "type Query { a:String } type Boom { a:String }"

    assert_error('Query name "Boom" is used', ComposeError) do
      compose_definitions({ "a" => a }, { query_name: "Boom" })
    end
  end

  def test_errors_for_mutation_type_name_conflict
    a = "type Query { a:String } type Mutation { a:String } type Boom { a:String }"

    assert_error('Mutation name "Boom" is used', ComposeError) do
      compose_definitions({ "a" => a }, { mutation_name: "Boom" })
    end
  end
end