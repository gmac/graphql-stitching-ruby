# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, validate resolvers' do

  def test_validates_only_one_resolver_query_per_type_location_key
    a = %{
      interface I { id:ID! }
      type T implements I { id:ID! name:String }
      type Query {
        t(id: ID!):T @stitch(key: "id")
        i(id: ID!):I @stitch(key: "id")
      }
    }
    b = %{type T { id:ID! size:Float } type Query { b:T }}

    assert_error("Multiple resolver queries for `T.id` found in a", ValidationError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_permits_multiple_resolver_query_keys_per_type_location
    a = %{
      type T { upc:ID! name:String }
      type Query { a(upc:ID!):T @stitch(key: "upc") }
    }
    b = %{
      type T { id:ID! upc:ID! }
      type Query {
        b1(upc:ID!):T @stitch(key: "upc")
        b2(id:ID!):T @stitch(key: "id")
      }
    }
    c = %{
      type T { id:ID! size:Int }
      type Query { c(id:ID!):T @stitch(key: "id") }
    }

    assert compose_definitions({ "a" => a, "b" => b, "c" => c })
  end

  def test_validates_resolver_present_when_providing_unique_fields
    a = %{type T { id:ID! name:String } type Query { a(id: ID!):T @stitch(key: "id") }}
    b = %{type T { id:ID! size:Float } type Query { b:T }}

    assert_error("A resolver query is required for `T` in b", ValidationError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_validates_resolver_present_in_multiple_locations_when_providing_unique_fields
    a = %{type T { id:ID! name:String } type Query { a(id: ID!):T @stitch(key: "id") }}
    b = %{type T { id:ID! size:Float } type Query { b:T }}
    c = %{type T { id:ID! size:Float } type Query { c:T }}

    assert_error("A resolver query is required for `T` in one of b, c locations", ValidationError) do
      compose_definitions({ "a" => a, "b" => b, "c" => c })
    end
  end

  def test_permits_no_resolver_query_for_types_that_can_be_fully_resolved_elsewhere
    a = %{type T { id:ID! name:String } type Query { a(id: ID!):T @stitch(key: "id") }}
    b = %{type T { id:ID! size:Float } type Query { b(id: ID!):T @stitch(key: "id") }}
    c = %{type T { id:ID! size:Float name:String } type Query { c:T }}

    assert compose_definitions({ "a" => a, "b" => b, "c" => c })
  end

  def test_permits_no_resolver_query_for_key_only_types
    a = %{type T { id:ID! name:String } type Query { a(id: ID!):T @stitch(key: "id") }}
    b = %{type T { id:ID! } type Query { b:T }}

    assert compose_definitions({ "a" => a, "b" => b })
  end

  def test_validates_subset_types_have_a_key
    a = %{type T { id:ID! name:String } type Query { a(id: ID!):T @stitch(key: "id") }}
    b = %{type T { name:String } type Query { b:T }}

    assert_error("A resolver key is required for `T` in b", ValidationError) do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_validates_bidirection_types_are_mutually_accessible
    a = %{
      type T { upc:ID! name:String }
      type Query { a(upc:ID!):T @stitch(key: "upc") }
    }
    b = %{
      type T { id:ID! weight:Int }
      type Query { b(id:ID!):T @stitch(key: "id") }
    }
    c = %{
      type T { id:ID! size:Int }
      type Query { c(id:ID!):T @stitch(key: "id") }
    }

    assert_error("Cannot route `T` resolvers in a", ValidationError) do
      compose_definitions({ "a" => a, "b" => b, "c" => c })
    end
  end

  def test_validates_key_only_types_are_mutually_accessible
    a = %|
      type T { upc:ID! }
      type Query { a(upc:ID!):T @stitch(key: "upc") }
    |
    b = %|
      type T { id:ID! }
      type Query { b(id:ID!):T @stitch(key: "id") }
    |
    c = %|
      type T { id:ID! }
      type Query { c(id:ID!):T @stitch(key: "id") }
    |

    assert_error("Cannot route `T` resolvers in a", ValidationError) do
      compose_definitions({ "a" => a, "b" => b, "c" => c })
    end
  end

  def test_validates_outbound_types_can_access_all_bidirection_types
    a = %{
      type T { upc:ID! }
      type Query { a:T }
    }
    b = %{
      type T { upc:ID! name:String }
      type Query { b(upc:ID!):T @stitch(key: "upc") }
    }
    c = %{
      type T { id:ID! size:Int }
      type Query { c(id:ID!):T @stitch(key: "id") }
    }

    assert_error("Cannot route `T` resolvers in a", ValidationError) do
      compose_definitions({ "a" => a, "b" => b, "c" => c })
    end
  end

  def test_permits_shared_types_across_locations_with_matching_compositions
    a = %{type T { id:ID! name: String } type Query { a:T }}
    b = %{type T { id:ID! name: String } type Query { b:T }}

    assert compose_definitions({ "a" => a, "b" => b })
  end

  def test_validates_shared_types_across_locations_must_have_matching_compositions
    a = %{type T { id:ID! name: String extra: String } type Query { a:T }}
    b = %{type T { id:ID! name: String } type Query { b:T }}

    assert_error("Shared type `T` must have consistent fields", ValidationError) do
      assert compose_definitions({ "a" => a, "b" => b })
    end
  end
end
