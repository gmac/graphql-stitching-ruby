# frozen_string_literal: true

module Schemas
  module Authorizations
    class Access < GraphQL::Schema::Directive
      graphql_name "access"
      locations OBJECT, FIELD_DEFINITION
      argument :scopes, [[String]]
    end

    class Boundary < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    FRUITS = [
      { id: '1', color: 'red', price: 2, __typename: 'Apple' },
      { id: '2', color: 'yellow', price: 3, __typename: 'Banana' },
      { id: '3', color: 'brown', price: 3, __typename: 'Coconut' },
    ].freeze

    class Alpha < GraphQL::Schema
      module Fruit
        include GraphQL::Schema::Interface
        field :id, ID, null: false
        field :color, String, null: false do
          directive(Access, scopes: [["read:color"]])
        end
      end

      class Apple < GraphQL::Schema::Object
        implements Fruit
      end

      class Banana < GraphQL::Schema::Object
        implements Fruit
      end

      class Coconut < GraphQL::Schema::Object
        directive(Access, scopes: [["read:coconut"]])
        implements Fruit
      end

      class Query < GraphQL::Schema::Object
        field :fruits, [Fruit, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def fruit(ids:)
          ids.map { |id| FRUITS.find { |f| id == f[:id] } }
        end
      end

      def self.resolve_type(_type, obj, _ctx)
        {
          "Apple" => Apple,
          "Banana" => Banana,
          "Coconut" => Coconut,
        }.fetch(obj[:__typename])
      end

      orphan_types Apple, Banana, Coconut
      query Query
    end

    class Bravo < GraphQL::Schema
      module Fruit
        include GraphQL::Schema::Interface
        field :id, ID, null: false
        field :price, Int, null: false do
          directive(Access, scopes: [["read:price"]])
        end
      end

      class Apple < GraphQL::Schema::Object
        implements Fruit
      end

      class Banana < GraphQL::Schema::Object
        implements Fruit
      end

      class Coconut < GraphQL::Schema::Object
        implements Fruit
      end

      class Query < GraphQL::Schema::Object
        field :fruits, [Fruit, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def fruit(ids:)
          ids.map { |id| FRUITS.find { |f| id == f[:id] } }
        end
      end

      def self.resolve_type(_type, obj, _ctx)
        {
          "Apple" => Apple,
          "Banana" => Banana,
          "Coconut" => Coconut,
        }.fetch(obj[:__typename])
      end

      orphan_types Apple, Banana, Coconut
      query Query
    end
  end
end
