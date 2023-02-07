# frozen_string_literal: true

module Schemas
  module Errors
    class Boundary < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    ELEMENTS_A = [
      { id: '10', name: 'neon' },
      { id: '36', name: 'krypton' },
    ].freeze

    ELEMENTS_B = [
      { id: '10', code: 'Ne', year: 1898 },
      { id: '18', code: 'Ar', year: 1894 },
    ].freeze

    class ElementsA < GraphQL::Schema
      class Element < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :elements_a, [Element, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def elements_a(ids:)
          ids.map do |id|
            ELEMENTS_A.find { _1[:id] == id } || GraphQL::ExecutionError.new("Not found")
          end
        end
      end

      query Query
    end

    class ElementsB < GraphQL::Schema
      class Element < GraphQL::Schema::Object
        field :id, ID, null: false
        field :code, String, null: true
        field :year, Int, null: true
      end

      class Query < GraphQL::Schema::Object
        field :elements_b, [Element, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def elements_b(ids:)
          ids.map do |id|
            ELEMENTS_B.find { _1[:id] == id } || GraphQL::ExecutionError.new("Not found")
          end
        end
      end

      query Query
    end
  end
end
