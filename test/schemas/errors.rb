# frozen_string_literal: true

module Schemas
  module Errors
    class Boundary < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    ISOTOPES_A = [
      { id: '1', name: 'Ne20' },
      { id: '2', name: 'Kr79' },
    ].freeze

    ISOTOPES_B = [
      { id: '2', halflife: '35d' },
    ].freeze

    ELEMENTS_A = [
      { id: '10', name: 'neon', isotopes: [ISOTOPES_A[0]], isotope: ISOTOPES_A[0] },
      { id: '36', name: 'krypton', isotopes: [ISOTOPES_A[1]], isotope: ISOTOPES_A[1] },
    ].freeze

    ELEMENTS_B = [
      { id: '10', code: 'Ne', year: 1898 },
      { id: '18', code: 'Ar', year: 1894 },
    ].freeze

    class ElementsA < GraphQL::Schema
      class Isotope < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
      end

      class Element < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
        field :isotopes, [Isotope, null: true], null: false
        field :isotope, Isotope, null: true
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

        field :element_a, Element, null: true do
          argument :id, ID, required: true
        end

        def element_a(id:)
          ELEMENTS_A.find { _1[:id] == id } || GraphQL::ExecutionError.new("Not found")
        end

        field :isotope_a, Isotope, null: true do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def isotope_a(id:)
          ISOTOPES_A.find { _1[:id] == id } || GraphQL::ExecutionError.new("Not found")
        end
      end

      query Query
    end

    class ElementsB < GraphQL::Schema
      class Isotope < GraphQL::Schema::Object
        field :id, ID, null: false
        field :halflife, String, null: false
      end

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

        field :isotope_b, Isotope, null: true do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def isotope_b(id:)
          ISOTOPES_B.find { _1[:id] == id } || GraphQL::ExecutionError.new("Not found")
        end
      end

      query Query
    end
  end
end
