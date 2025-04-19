# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Supergraph#from_definition" do
  def setup
    alpha = %|
      interface I { id:ID! }
      type T implements I { id:ID! a:String }
      type Query { a(id:ID!):I @stitch(key: "id") }
    |
    bravo = %|
      type T { id:ID! b:String }
      type Query { b(id:ID!):T @stitch(key: "id") }
    |

    @supergraph = compose_definitions({ "alpha" => alpha, "bravo" => bravo })
    @schema_sdl = @supergraph.to_definition
  end

  # is this a composer test now...?
  def test_to_definition_annotates_schema
    @schema_sdl = squish_string(@schema_sdl)
    assert @schema_sdl.include?("directive @key")
    assert @schema_sdl.include?("directive @resolver")
    assert @schema_sdl.include?("directive @source")
    assert @schema_sdl.include?(squish_string(%|
      interface I
        @key(key: "id", location: "alpha")
        @resolver(location: "alpha", key: "id", field: "a", arguments: "id: $.id", argumentTypes: "id: ID!") {
    |))
    assert @schema_sdl.include?(squish_string(%|
      type T implements I
        @key(key: "id", location: "alpha")
        @key(key: "id", location: "bravo")
        @resolver(location: "bravo", key: "id", field: "b", arguments: "id: $.id", argumentTypes: "id: ID!")
        @resolver(location: "alpha", key: "id", field: "a", arguments: "id: $.id", argumentTypes: "id: ID!", typeName: "I") {
    |))
    assert @schema_sdl.include?(%|id: ID! @source(location: "alpha") @source(location: "bravo")|)
    assert @schema_sdl.include?(%|a: String @source(location: "alpha")|)
    assert @schema_sdl.include?(%|b: String @source(location: "bravo")|)
    assert @schema_sdl.include?(%|a(id: ID!): I @source(location: "alpha")|)
    assert @schema_sdl.include?(%|b(id: ID!): T @source(location: "bravo")|)
  end

  def test_from_definition_restores_supergraph
    supergraph_import = GraphQL::Stitching::Supergraph.from_definition(@schema_sdl, executables: {
      "alpha" => Proc.new { true },
      "bravo" => Proc.new { true },
    })

    assert_equal @supergraph.fields, supergraph_import.fields
    assert_equal ["alpha", "bravo"], supergraph_import.locations.sort
    assert_equal @supergraph.schema.types.keys.sort, supergraph_import.schema.types.keys.sort
    assert_equal @supergraph.resolvers, supergraph_import.resolvers
  end

  def test_normalizes_executable_location_names
    supergraph_import = GraphQL::Stitching::Supergraph.from_definition(@schema_sdl, executables: {
      alpha: Proc.new { true },
      bravo: Proc.new { true },
    })

    assert_equal ["alpha", "bravo"], supergraph_import.locations.sort
  end

  def test_errors_for_invalid_executables
    assert_error "Invalid executable provided for location" do
      GraphQL::Stitching::Supergraph.from_definition(@schema_sdl, executables: {
        alpha: Proc.new { true },
        bravo: "nope",
      })
    end
  end

  def test_errors_for_missing_executables
    assert_error "Invalid executable provided for location" do
      GraphQL::Stitching::Supergraph.from_definition(@schema_sdl, executables: {
        alpha: Proc.new { true },
      })
    end
  end
end
