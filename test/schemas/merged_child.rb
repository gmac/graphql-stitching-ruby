# frozen_string_literal: true

module Schemas
  module MergedChild
    class StitchingResolver < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String, required: true
      argument :arguments, String, required: false
      repeatable true
    end

    AUTHOR = {
      id: "1",
      name: "Frank Herbert",
      book: {
        id: "1",
        title: "Dune",
        year: 1965,
      },
    }.freeze

    class ParentSchema < GraphQL::Schema
      class Book < GraphQL::Schema::Object
        field :id, ID, null: false
        field :title, String, null: false
      end

      class Author < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
        field :book, Book, null: true
      end

      class Query < GraphQL::Schema::Object
        field :author, Author, null: false

        def author
          AUTHOR
        end

        field :book, Book, null: true do
          directive StitchingResolver, key: "id"
          argument :id, ID, required: true
        end

        def book(id:)
          AUTHOR[:book] if AUTHOR[:book][:id] == id
        end
      end

      query Query
    end

    class ChildSchema < GraphQL::Schema
      class Book < GraphQL::Schema::Object
        field :id, ID, null: false
        field :year, Int, null: false
      end

      class Query < GraphQL::Schema::Object
        field :book, Book, null: true do
          directive StitchingResolver, key: "id"
          argument :id, ID, required: true
        end

        def book(id:)
          AUTHOR[:book] if AUTHOR[:book][:id] == id
        end
      end

      query Query
    end
  end
end
