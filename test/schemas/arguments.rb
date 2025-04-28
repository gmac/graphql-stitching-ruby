# frozen_string_literal: true

module Schemas
  module Arguments
    DIRECTORS = [
      { id: "1", name: "Steven Spielberg" },
      { id: "2", name: "Christopher Nolan" },
    ].freeze

    STUDIOS = [
      { id: "1", name: "Universal" },
      { id: "2", name: "Lucasfilm" },
      { id: "3", name: "Syncopy" },
    ].freeze

    GENRES = [
      { id: "1", name: "action" },
      { id: "2", name: "adventure" },
      { id: "3", name: "sci-fi" },
      { id: "4", name: "thriller" },
    ].freeze

    MOVIES = [
      {
        id: "1",
        title: "Jurassic Park",
        status: "STREAMING",
        genres: [GENRES[1], GENRES[2]],
        director: DIRECTORS[0],
        studio: STUDIOS[0],
      },
      {
        id: "2",
        title: "Indiana Jones: Raiders of the Lost Arc",
        status: "IN_THEATERS",
        genres: [GENRES[0], GENRES[1]],
        director: DIRECTORS[0],
        studio: STUDIOS[1],
      },
      {
        id: "3",
        title: "Inception",
        status: "STREAMING",
        genres: [GENRES[0], GENRES[3]],
        director: DIRECTORS[1],
        studio: STUDIOS[2],
      },
    ].freeze

    class Arguments1 < GraphQL::Schema
      class Director < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class Genre < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class Studio < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class Movie < GraphQL::Schema::Object
        field :id, ID, null: false
        field :title, String, null: false
        field :director, Director, null: false
        field :genres, [Genre], null: false
        field :studio, Studio, null: false
      end

      class Query < GraphQL::Schema::Object
        field :movies, [Movie, null: true], null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :ids, [ID], required: true
        end

        def movies(ids:)
          ids.map { |id| MOVIES.find { _1[:id] == id } }
        end

        field :all_movies, [Movie], null: false

        def all_movies
          MOVIES
        end
      end

      query Query
    end

    class Arguments2 < GraphQL::Schema
      class Director < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
      end

      class Studio < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
      end

      class Genre < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
      end

      class MovieStatus < GraphQL::Schema::Enum
        value "IN_THEATERS"
        value "STREAMING"
      end

      class Movie < GraphQL::Schema::Object
        field :id, ID, null: false
        field :status, MovieStatus, null: true
      end

      class ComplexKey <  GraphQL::Schema::InputObject
        argument :id, String, required: false
        argument :subkey, ComplexKey, required: false
      end

      class ScalarKey <  GraphQL::Schema::Scalar
        graphql_name "_Any"
      end

      class Query < GraphQL::Schema::Object
        field :movies2, [Movie, null: true], null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id", arguments: "ids: $.id, status: STREAMING"
          argument :ids, [ID], required: true
          argument :status, MovieStatus, required: true
        end

        def movies2(ids:, status: nil)
          visible_movies = MOVIES.filter { _1[:status] == status }
          ids.map { |id| visible_movies.find { _1[:id] == id } }
        end

        field :director, Director, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id", arguments: "key: { subkey: { id: $.id } }"
          argument :key, ComplexKey, required: true
        end

        def director(key:)
          DIRECTORS.find { _1[:id] == key.dig(:subkey, :id) }
        end

        field :studios, [Studio, null: true], null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id", arguments: "keys: { subkey: { id: $.id } }"
          argument :keys, [ScalarKey], required: true
        end

        def studios(keys:)
          keys.map { |key| STUDIOS.find { |s| s[:id] == key.dig("subkey", "id") } }
        end

        field :genres, [Genre, null: true], null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id", arguments: "keys: $.id, prefix: 'action'"
          argument :keys, [ID], required: true
          argument :prefix, String, required: false
        end

        def genres(keys:, prefix:)
          keys.map do |key|
            genre = GENRES.find { _1[:id] == key }
            if genre && genre[:name] != prefix
              genre.merge(name: "#{prefix}/#{genre[:name]}")
            else
              genre
            end
          end
        end
      end

      query Query
    end
  end
end
