# frozen_string_literal: true

module Schemas
  module Conditionals
    class Boundary < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    FRUITS = [
      { id: '1', extension_id: '11', __typename: 'Apple' },
      { id: '2', extension_id: '22', __typename: 'Banana' },
    ].freeze

    class Extensions < GraphQL::Schema
      class AppleExtension < GraphQL::Schema::Object
        field :id, ID, null: false
        field :color, String, null: false
      end

      class BananaExtension < GraphQL::Schema::Object
        field :id, ID, null: false
        field :shape, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :apple_extension, AppleExtension, null: true do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def apple_extension(id:)
          { id: id, color: "red" }
        end

        field :banana_extension, BananaExtension, null: true do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def banana_extension(id:)
          { id: id, shape: "crescent" }
        end
      end

      query Query
    end

    class Abstracts < GraphQL::Schema
      class AppleExtension < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class Apple < GraphQL::Schema::Object
        field :id, ID, null: false
        field :extensions, AppleExtension, null: false

        def extensions
          { id: object[:extension_id] }
        end
      end

      class BananaExtension < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class Banana < GraphQL::Schema::Object
        field :id, ID, null: false
        field :extensions, BananaExtension, null: false

        def extensions
          { id: object[:extension_id] }
        end
      end

      class Fruit < GraphQL::Schema::Union
        possible_types Apple, Banana
      end

      class Query < GraphQL::Schema::Object
        field :fruits, [Fruit, null: true], null: false do
          argument :ids, [ID], required: true
        end

        def fruits(ids:)
          ids.map { |id| FRUITS.find { _1[:id] == id } }
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
  end
end
