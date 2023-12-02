# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging boundary queries' do
  def test_creates_boundary_map
    a = %|type Test { id: ID!, a: String } type Query { a(id: ID!):Test @stitch(key: "id") }|
    b = %|type Test { id: ID!, b: String } type Query { b(ids: [ID!]!):[Test]! @stitch(key: "id") }|
    supergraph = compose_definitions({ "a" => a, "b" => b })

    expected_boundaries_map = {
      "Test" => [
        GraphQL::Stitching::Boundary.new(
          location: "a",
          key: "id",
          field: "a",
          arg: "id",
          list: false,
          federation: false,
          type_name: "Test"
        ),
        GraphQL::Stitching::Boundary.new(
          location: "b",
          key: "id",
          field: "b",
          arg: "ids",
          list: true,
          federation: false,
          type_name: "Test"
        ),
      ],
    }

    assert_equal expected_boundaries_map, supergraph.boundaries
  end

  def test_merges_boundaries_with_multiple_keys
    # repeatable directives don't work before v2.0.15
    skip unless minimum_graphql_version?("2.0.15")

    a = %|
      type T { upc:ID! }
      type Query { a(upc:ID!):T @stitch(key: "upc") }
    |
    b = %|
      type T { id:ID! upc:ID! }
      type Query { b(id: ID, upc:ID):T @stitch(key: "id:id") @stitch(key: "upc:upc") }
    |
    c = %|
      type T { id:ID! }
      type Query { c(id:ID!):T @stitch(key: "id") }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c })

    assert_boundary(supergraph, "T", location: "a", key: "upc", field: "a", arg: "upc")
    assert_boundary(supergraph, "T", location: "b", key: "upc", field: "b", arg: "upc")
    assert_boundary(supergraph, "T", location: "b", key: "id", field: "b", arg: "id")
    assert_boundary(supergraph, "T", location: "c", key: "id", field: "c", arg: "id")
  end

  def test_expands_interface_boundary_accessors_to_relevant_types
    a = %|
      interface Fruit { id:ID! }
      type Apple implements Fruit { id:ID! name:String }
      type Banana implements Fruit { id:ID! name:String }
      type Coconut implements Fruit { id:ID! name:String }
      type Query { fruit(id:ID!):Fruit @stitch(key: "id") }
    |
    b = %|
      type Apple { id:ID! color:String }
      type Banana { id:ID! color:String }
      type Query {
        a(id:ID!):Apple @stitch(key: "id")
        b(id:ID!):Banana @stitch(key: "id")
      }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })

    assert_equal 1, supergraph.boundaries["Fruit"].length
    assert_equal 2, supergraph.boundaries["Apple"].length
    assert_equal 2, supergraph.boundaries["Banana"].length
    assert_nil supergraph.boundaries["Coconut"]

    assert_boundary(supergraph, "Fruit", location: "a", key: "id", field: "fruit", arg: "id")
    assert_boundary(supergraph, "Apple", location: "a", key: "id", field: "fruit", arg: "id")
    assert_boundary(supergraph, "Banana", location: "a", key: "id", field: "fruit", arg: "id")
    assert_boundary(supergraph, "Apple", location: "b", key: "id", field: "a", arg: "id")
    assert_boundary(supergraph, "Banana", location: "b", key: "id", field: "b", arg: "id")
  end

  def test_expands_union_boundary_accessors_to_relevant_types
    a = %|
      type Apple { id:ID! name:String }
      type Banana { id:ID! name:String }
      union Fruit = Apple \| Banana
      type Query {
        fruit(id:ID!):Fruit @stitch(key: "id")
      }
    |
    b = %|
      type Apple { id:ID! color:String }
      type Coconut { id:ID! name:String }
      union Fruit = Apple \| Coconut
      type Query {
        a(id:ID!):Apple @stitch(key: "id")
        c(id:ID!):Coconut
      }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal 1, supergraph.boundaries["Fruit"].length
    assert_equal 2, supergraph.boundaries["Apple"].length
    assert_nil supergraph.boundaries["Banana"]
    assert_nil supergraph.boundaries["Coconut"]

    assert_boundary(supergraph, "Fruit", location: "a", key: "id", field: "fruit", arg: "id")
    assert_boundary(supergraph, "Apple", location: "a", key: "id", field: "fruit", arg: "id")
    assert_boundary(supergraph, "Apple", location: "b", key: "id", field: "a", arg: "id")
  end

  private

  def assert_boundary(supergraph, type_name, location:, key: nil, field: nil, arg: nil)
    boundary = supergraph.boundaries[type_name].find do |b|
      conditions = []
      conditions << (b.location == location)
      conditions << (b.field == field) if field
      conditions << (b.arg == arg) if arg
      conditions << (b.key == key) if key
      conditions.all?
    end
    assert boundary, "No boundary found for #{[location, type_name, key, field, arg].join(".")}"
  end
end
