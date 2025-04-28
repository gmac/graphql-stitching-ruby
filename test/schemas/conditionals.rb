# frozen_string_literal: true

module Schemas
  module Conditionals
    FRUITS = [
      { id: '1', extension_id: '11', __typename: 'Apple' },
      { id: '2', extension_id: '22', __typename: 'Banana' },
    ].freeze

    class ExtensionsA < GraphQL::Schema
      class AppleExtension < GraphQL::Schema::Object
        field :id, ID, null: false
        field :color, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :apple_extension, AppleExtension, null: true do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def apple_extension(id:)
          { id: id, color: "red" }
        end
      end

      query Query
    end

    class ExtensionsB < GraphQL::Schema
      class BananaExtension < GraphQL::Schema::Object
        field :id, ID, null: false
        field :shape, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :banana_extension, BananaExtension, null: true do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def banana_extension(id:)
          { id: id, shape: "crescent" }
        end
      end

      query Query
    end

    class Abstracts < GraphQL::Schema
      module Extension
        include GraphQL::Schema::Interface
        field :id, ID, null: false
      end

      module HasExtension
        include GraphQL::Schema::Interface
        field :abstract_extension, Extension, null: false

        def abstract_extension
          { id: object[:extension_id], __typename: "#{object[:__typename]}Extension" }
        end
      end

      class AppleExtension < GraphQL::Schema::Object
        implements Extension
      end

      class Apple < GraphQL::Schema::Object
        implements HasExtension
        field :id, ID, null: false
        field :extensions, AppleExtension, null: false

        def extensions
          { id: object[:extension_id], __typename: "AppleExtension" }
        end
      end

      class BananaExtension < GraphQL::Schema::Object
        implements Extension
      end

      class Banana < GraphQL::Schema::Object
        implements HasExtension
        field :id, ID, null: false
        field :extensions, BananaExtension, null: false

        def extensions
          { id: object[:extension_id], __typename: "BananaExtension" }
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
        "AppleExtension" => AppleExtension,
        "BananaExtension" => BananaExtension,
      }.freeze

      def self.resolve_type(_type, obj, _ctx)
        TYPES.fetch(obj[:__typename])
      end

      query Query
    end
  end
end
