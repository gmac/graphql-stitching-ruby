# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::Compose::MergeObjectTest < Minitest::Test
  MOVIES_SCHEMA = %{
    directive @boundary(key: String!) on FIELD_DEFINITION

    type Movie {
      id: ID!
      title: String!
    }

    type Genre {
      name: String!
    }

    type Query {
      movie(id: ID!): Movie @boundary(key: "id")
      genre: Genre!
    }
  }

  SHOWTIMES_SCHEMA = %{
    directive @boundary(key: String!) on FIELD_DEFINITION

    type Movie {
      id: ID!
      title: String
      showtimes: [Showtime!]!
    }

    type Showtime {
      time: String!
    }

    type Query {
      movie(id: ID!): Movie @boundary(key: "id")
      showtime: Showtime!
    }
  }

  def test_combines_objects_and_their_fields
    schema, _delegation_map = compose_definitions({
      "movies" => MOVIES_SCHEMA,
      "showtimes" => SHOWTIMES_SCHEMA,
    })

    schema_objects = extract_types_of_kind(schema, "OBJECT")
    assert_equal ["Genre", "Movie", "Query", "Showtime"], schema_objects.map(&:graphql_name).sort
    assert_equal ["id", "showtimes", "title"], schema.types["Movie"].fields.keys.sort
    assert_equal ["genre", "movie", "showtime"], schema.types["Query"].fields.keys.sort
  end

  def test_merged_fields_use_common_nullability
    a = "type Test { field: String! } type Query { test:Test }"
    b = "type Test { field: String! } type Query { test:Test }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "String!", print_type(schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_use_weakest_nullability
    a = "type Test { field: String! } type Query { test:Test }"
    b = "type Test { field: String } type Query { test:Test }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "String", print_type(schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_must_have_matching_named_types
    a = "type Test { field: String } type Query { test:Test }"
    b = "type Test { field: Int } type Query { test:Test }"

    # verify error!
    assert_raises do
      schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_fields_use_common_list_structure
    a = "type Test { field: [String!]! } type Query { test:Test }"
    b = "type Test { field: [String!]! } type Query { test:Test }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[String!]!", print_type(schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_use_weakest_list_structure
    a = "type Test { field: [String!]! } type Query { test:Test }"
    b = "type Test { field: [String!] } type Query { test:Test }"
    c = "type Test { field: [String]! } type Query { test:Test }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b, "c" => c })
    assert_equal "[String]", print_type(schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_allow_deep_list_structures
    a = "type Test { field: [[String!]!]! } type Query { test:Test }"
    b = "type Test { field: [[String]!] } type Query { test:Test }"

    schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[[String]!]", print_type(schema.types["Test"].fields["field"].type)
  end

  def test_merged_fields_must_have_matching_list_structures
    a = "type Test { field: [[String!]] } type Query { test:Test }"
    b = "type Test { field: [String!] } type Query { test:Test }"

    # verify error!
    assert_raises do
      schema, _delegation_map = compose_definitions({ "a" => a, "b" => b })
    end
  end
end
