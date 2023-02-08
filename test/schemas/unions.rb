# frozen_string_literal: true

module TestSchema
  module Unions
    class Boundary < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    FRUITS = [
      { id: '1', a: 'a1', b: 'b1', c: 'c1', __typename: 'Apple' },
      { id: '2', a: 'a2', b: 'b2', c: 'c2', __typename: 'Apple' },
      { id: '3', a: 'a3', b: 'b3', c: 'c3', __typename: 'Banana' },
      { id: '4', a: 'a4', b: 'b4', c: 'c4', __typename: 'Coconut' },
    ].freeze

    class SchemaA < GraphQL::Schema
      class Apple < GraphQL::Schema::Object
        field :id, ID, null: false
        field :a, String, null: false
      end

      class Banana < GraphQL::Schema::Object
        field :id, ID, null: false
        field :a, String, null: false
      end

      class Fruit < GraphQL::Schema::Union
        possible_types Apple, Banana
      end

      class Query < GraphQL::Schema::Object
        field :fruit_a, Fruit, null: true do
          argument :id, ID, required: true
        end

        def fruit_a(id:)
          FRUITS.find { _1[:id] == id }
        end

        field :fruits_a, [Fruit, null: true], null: false do
          argument :ids, [ID], required: true
        end

        def fruits_a(ids:)
          ids.map { |id| FRUITS.find { _1[:id] == id && /Apple|Banana/.match(_1[:__typename]) } }
        end

        field :apple_a, Apple, null: true do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def apple_a(id:)
          FRUITS.find { _1[:id] == id && _1[:__typename] == 'Apple' }
        end

        field :banana_b, Banana, null: true do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def banana_b(id:)
          FRUITS.find { _1[:id] == id && _1[:__typename] == 'Banana' }
        end
      end

      TYPES = {
        "Apple" => Apple,
        "Banana" => Banana,
      }.freeze

      def self.resolve_type(_type, obj, _ctx)
        TYPES.fetch(obj[:__typename])
      end

      query Query
    end

    class SchemaB < GraphQL::Schema
      class Apple < GraphQL::Schema::Object
        field :id, ID, null: false
        field :b, String, null: false
      end

      class Banana < GraphQL::Schema::Object
        field :id, ID, null: false
        field :b, String, null: false
      end

      class Coconut < GraphQL::Schema::Object
        field :id, ID, null: false
        field :b, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :apple_b, Apple, null: true do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def apple_b(id:)
          FRUITS.find { _1[:id] == id && _1[:__typename] == 'Apple' }
        end

        field :banana_b, Banana, null: true do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def banana_b(id:)
          FRUITS.find { _1[:id] == id && _1[:__typename] == 'Banana' }
        end

        field :coconut_b, Coconut, null: true do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def coconut_b(id:)
          FRUITS.find { _1[:id] == id && _1[:__typename] == 'Coconut' }
        end
      end

      query Query
    end

    class SchemaC < GraphQL::Schema
      class Apple < GraphQL::Schema::Object
        field :id, ID, null: false
        field :c, String, null: false
      end

      class Coconut < GraphQL::Schema::Object
        field :id, ID, null: false
        field :c, String, null: false
      end

      class Fruit < GraphQL::Schema::Union
        possible_types Apple, Coconut
      end

      class Query < GraphQL::Schema::Object
        field :fruit_c, [Fruit, null: true], null: false do
          argument :ids, [ID], required: true
        end

        def fruit_c(id:)
          FRUITS.find { _1[:id] == id }
        end

        field :fruits_c, [Fruit, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def fruits_c(ids:)
          ids.map { |id| FRUITS.find { _1[:id] == id && /Apple|Coconut/.match(_1[:__typename]) } }
        end

        field :apple_c, Apple, null: true do
          argument :id, ID, required: true
        end

        def apple_c(id:)
          FRUITS.find { _1[:id] == id && _1[:__typename] == 'Apple' }
        end

        field :coconut_c, Coconut, null: true do
          argument :id, ID, required: true
        end

        def coconut_c(id:)
          FRUITS.find { _1[:id] == id && _1[:__typename] == 'Coconut' }
        end
      end

      TYPES = {
        "Apple" => Apple,
        "Coconut" => Coconut,
      }.freeze

      def self.resolve_type(_type, obj, _ctx)
        TYPES.fetch(obj[:__typename])
      end

      query Query
    end
  end
end
