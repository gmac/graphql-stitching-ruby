# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging root objects' do

  def test_merges_fields_of_root_scopes
    a = "type Query { a:String } type Mutation { a:String } type Subscription { a:String }"
    b = "type Query { b:String } type Mutation { b:String } type Subscription { b:String }"

    info = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["a","b"], info.schema.types["Query"].fields.keys.sort
    assert_equal ["a","b"], info.schema.types["Mutation"].fields.keys.sort
    assert_equal ["a","b"], info.schema.types["Subscription"].fields.keys.sort
  end

  def test_merges_fields_of_root_scopes_from_custom_names
    a = "type RootQ { a:String } type RootM { a:String } schema { query:RootQ mutation:RootM }"
    b = "type Query { b:String } type Mutation { b:String }"

    info = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["a","b"], info.schema.types["Query"].fields.keys.sort
    assert_equal ["a","b"], info.schema.types["Mutation"].fields.keys.sort
  end

  def test_merges_fields_of_root_scopes_into_custom_names
    a = "type Query { a:String } type Mutation { a:String }"
    b = "type Query { b:String } type Mutation { b:String }"

    info = compose_definitions({ "a" => a, "b" => b }, {
      query_name: "RootQuery",
      mutation_name: "RootMutation",
    })

    assert_equal ["a","b"], info.schema.types["RootQuery"].fields.keys.sort
    assert_equal ["a","b"], info.schema.types["RootMutation"].fields.keys.sort
    assert_nil info.schema.get_type("Query")
    assert_nil info.schema.get_type("Mutation")
  end

  def test_errors_for_query_type_name_conflict
    a = "type Query { a:String } type Boom { a:String }"

    assert_error('Query name "Boom" is used', CompositionError) do
      compose_definitions({ "a" => a }, { query_name: "Boom" })
    end
  end

  def test_errors_for_mutation_type_name_conflict
    a = "type Query { a:String } type Mutation { a:String } type Boom { a:String }"

    assert_error('Mutation name "Boom" is used', CompositionError) do
      compose_definitions({ "a" => a }, { mutation_name: "Boom" })
    end
  end

  def test_prioritizes_last_root_field_location_by_default
    a = "type Query { f:String } type Mutation { f:String }"
    b = "type Query { f:String } type Mutation { f:String }"

    delegation_map = compose_definitions({ "a" => a, "b" => b }).fields

    assert_equal ["b", "a"], delegation_map["Query"]["f"]
    assert_equal ["b", "a"], delegation_map["Mutation"]["f"]
  end

  def test_prioritizes_root_field_location_selector_choice
    a = "type Query { f:String } type Mutation { f:String }"
    b = "type Query { f:String } type Mutation { f:String }"

    delegation_map = compose_definitions({ "a" => a, "b" => b }, {
      root_field_location_selector: ->(_locations, _info) { "a" }
    }).fields

    assert_equal ["a", "b"], delegation_map["Query"]["f"]
    assert_equal ["a", "b"], delegation_map["Mutation"]["f"]
  end

  def test_prioritizes_root_entrypoints_locations
    a = "type Query { f:String } type Mutation { f:String }"
    b = "type Query { f:String } type Mutation { f:String }"

    delegation_map = compose_definitions({ "a" => a, "b" => b }, {
      root_entrypoints: { "Query.f" => "a", "Mutation.f" => "a" },
    }).fields

    assert_equal ["a", "b"], delegation_map["Query"]["f"]
    assert_equal ["a", "b"], delegation_map["Mutation"]["f"]
  end

  def test_errors_for_invalid_root_entrypoints
    a = "type Query { f:String } type Mutation { f:String }"
    b = "type Query { f:String } type Mutation { f:String }"

    assert_error("Invalid `root_entrypoints` configuration", CompositionError) do
      compose_definitions({ "a" => a, "b" => b }, {
        root_entrypoints: { "Query.f" => "invalid" },
      })
    end
  end
end
