# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging objects' do

  def test_merges_object_descriptions
    a = %{"""a""" type Test { field: String } type Query { test:Test }}
    b = %{"""b""" type Test { field: String } type Query { test:Test }}

    info = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", info.schema.types["Test"].description
  end

  def test_merges_interface_memberships
    a = %{interface A { id:ID } type C implements A { id:ID } type Query { c:C }}
    b = %{interface B { id:ID } type C implements B { id:ID } type Query { c:C }}

    info = compose_definitions({ "a" => a, "b" => b })

    assert_equal ["A", "B"], info.schema.types["C"].interfaces.map(&:graphql_name).sort
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
    info = compose_definitions({
      "movies" => MOVIES_SCHEMA,
      "showtimes" => SHOWTIMES_SCHEMA,
    })

    schema_objects = extract_types_of_kind(info.schema, "OBJECT")
    assert_equal ["Genre", "Movie", "Query", "Showtime"], schema_objects.map(&:graphql_name).sort
    assert_equal ["id", "showtimes", "title"], info.schema.types["Movie"].fields.keys.sort
    assert_equal ["genre", "movie", "showtime"], info.schema.types["Query"].fields.keys.sort
  end
end
