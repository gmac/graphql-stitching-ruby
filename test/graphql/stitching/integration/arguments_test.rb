# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/arguments"

describe 'GraphQL::Stitching, arguments' do
  def setup
    @supergraph = compose_definitions({
      "args1" => Schemas::Arguments::Arguments1,
      "args2" => Schemas::Arguments::Arguments2,
    })
  end

  def test_stitches_with_enum_argument
    query = %|{ allMovies { id status } }|
    result = plan_and_execute(@supergraph, query)
    expected = {
      "allMovies" => [
        { "id" => "1", "status" => "STREAMING" },
        { "id" => "2", "status" => nil },
        { "id" => "3", "status" => "STREAMING" },
      ],
    }

    assert_equal expected, result["data"]
  end

  def test_stitches_with_input_object_key
    query = %|{ allMovies { id director { name } } }|
    result = plan_and_execute(@supergraph, query)
    expected = {
      "allMovies" => [
        { "id" => "1", "director" => { "name" => "Steven Spielberg" } },
        { "id" => "2", "director" => { "name" => "Steven Spielberg" } },
        { "id" => "3", "director" => { "name" => "Christopher Nolan" } },
      ],
    }

    assert_equal expected, result["data"]
  end

  def test_stitches_with_scalar_key
    query = %|{ allMovies { id studio { name } } }|
    result = plan_and_execute(@supergraph, query)
    expected = {
      "allMovies" => [
        { "id" => "1", "studio" => { "name" => "Universal" } },
        { "id" => "2", "studio" => { "name" => "Lucasfilm" } },
        { "id" => "3", "studio" => { "name" => "Syncopy" } },
      ],
    }

    assert_equal expected, result["data"]
  end

  def test_stitches_with_literal_arguments
    query = %|{ allMovies { id genres { name } } }|
    result = plan_and_execute(@supergraph, query)
    expected = {
      "allMovies" => [
        { "id" => "1", "genres" => [{ "name" => "action/adventure" }, { "name" => "action/sci-fi" }] },
        { "id" => "2", "genres" => [{ "name" => "action" }, { "name" => "action/adventure" }] },
        { "id" => "3", "genres" => [{ "name" => "action" }, { "name" => "action/thriller" }] },
      ],
    }

    assert_equal expected, result["data"]
  end
end
