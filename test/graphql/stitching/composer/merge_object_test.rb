# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging objects' do

  def test_merges_object_descriptions
    a = %{"""a""" type Test { field: String } type Query { test:Test }}
    b = %{"""b""" type Test { field: String } type Query { test:Test }}

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      formatter: TestFormatter.new,
    })

    assert_equal "a/b", supergraph.schema.types["Test"].description
  end

  def test_merges_object_directives
    a = %|
      directive @fizzbuzz(arg: String!) on OBJECT
      type Test @fizzbuzz(arg: "a") { field: String }
      type Query { test:Test }
    |

    b = %|
      directive @fizzbuzz(arg: String!) on OBJECT
      type Test @fizzbuzz(arg: "b") { field: String }
      type Query { test:Test }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      formatter: TestFormatter.new,
    })

    assert_equal "a/b", supergraph.schema.types["Test"].directives.first.arguments.keyword_arguments[:arg]
  end

  def test_merges_interface_memberships
    a = %{interface A { id:ID } type C implements A { id:ID } type Query { c:C }}
    b = %{interface B { id:ID } type C implements B { id:ID } type Query { c:C }}

    supergraph = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["A", "B"], supergraph.schema.types["C"].interfaces.map(&:graphql_name).sort
  end

  MOVIES_SCHEMA = %{
    type Movie {
      id: ID!
      title: String!
    }

    type Genre {
      name: String!
    }

    type Query {
      movie(id: ID!): Movie @stitch(key: "id")
      genre: Genre!
    }
  }

  SHOWTIMES_SCHEMA = %{
    type Movie {
      id: ID!
      title: String
      showtimes: [Showtime!]!
    }

    type Showtime {
      time: String!
    }

    type Query {
      movie(id: ID!): Movie @stitch(key: "id")
      showtime: Showtime!
    }
  }

  def test_combines_objects_and_their_fields
    supergraph = compose_definitions({
      "movies" => MOVIES_SCHEMA,
      "showtimes" => SHOWTIMES_SCHEMA,
    })

    schema_objects = extract_types_of_kind(supergraph.schema, "OBJECT")
    assert_equal ["Genre", "Movie", "Query", "Showtime"], schema_objects.map(&:graphql_name).sort
    assert_equal ["id", "showtimes", "title"], supergraph.schema.types["Movie"].fields.keys.sort
    assert_equal ["genre", "movie", "showtime"], supergraph.schema.types["Query"].fields.keys.sort
  end
end
