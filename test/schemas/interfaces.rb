# frozen_string_literal: true

module Schemas
  module Interfaces
    class Boundary < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    PRODUCTS = [
      { id: '1', name: 'iPhone', price: 699.99, __typename: 'Product' },
      { id: '2', name: 'Apple Watch', price: 399.99, __typename: 'Product' },
      { id: '3', name: 'Super Baking Cookbook', price: 15.99, __typename: 'Product' },
      { id: '4', name: 'Best Selling Novel', price: 7.99, __typename: 'Product' },
      { id: '5', name: 'iOS Survival Guide', price: 24.99, __typename: 'Product' },
    ].freeze

    BUNDLES = [
      { id: '1', name: 'Apple Gear', price: 999.99, product_ids: ['1', '2'], __typename: 'Bundle' },
      { id: '2', name: 'Epicures', price: 20.99, product_ids: ['3', '4'], __typename: 'Bundle' },
    ].freeze

    GIZMOS = [
      { id: '1', name: 'Widget', price: 10.99, __typename: 'Gizmo' },
      { id: '2', name: 'Sprocket', price: 9.99, __typename: 'Gizmo' },
    ].freeze

    # Products

    class Products < GraphQL::Schema
      module Buyable
        include GraphQL::Schema::Interface
        field :id, ID, null: false
        field :name, String, null: false
        field :price, Float, null: false
      end

      class Product < GraphQL::Schema::Object
        implements Buyable
      end

      module Split
        include GraphQL::Schema::Interface
        field :id, ID, null: false
        field :name, String, null: false
      end

      class Gizmo < GraphQL::Schema::Object
        implements Split
      end

      class Query < GraphQL::Schema::Object
        field :products, [Product, null: true], null: false do
          argument :ids, [ID], required: true
        end

        def product(ids:)
          ids.map { |id| PRODUCTS.find { _1[:id] == id } }
        end

        field :products_buyables, [Buyable, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def products_buyables(ids:)
          ids.map { |id| PRODUCTS.find { _1[:id] == id } }
        end

        field :products_split, [Split, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def products_split(ids:)
          ids.map { |id| GIZMOS.find { _1[:id] == id } }
        end
      end

      TYPES = {
        "Product" => Product,
        "Gizmo" => Gizmo,
      }.freeze

      def self.resolve_type(_type, obj, _ctx)
        TYPES.fetch(obj[:__typename])
      end

      query Query
    end

    # Bundles

    class Bundles < GraphQL::Schema
      module Buyable
        include GraphQL::Schema::Interface
        field :id, ID, null: false
      end

      class Product < GraphQL::Schema::Object
        implements Buyable
      end

      class Bundle < GraphQL::Schema::Object
        implements Buyable
        field :name, String, null: false
        field :price, Float, null: false
        field :products, [Product], null: false

        def products
          object[:product_ids].map { { id: _1, __typename: 'Product' } }
        end
      end

      module Split
        include GraphQL::Schema::Interface
        field :id, ID, null: false
        field :price, Float, null: false
      end

      class Gizmo < GraphQL::Schema::Object
        implements Split
      end

      class Query < GraphQL::Schema::Object
        field :bundles, [Bundle, null: true], null: false do
          argument :ids, [ID], required: true
        end

        def bundles(ids:)
          ids.map { |id| BUNDLES.find { _1[:id] == id } }
        end

        field :bundles_buyables, [Buyable, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def bundles_buyables(ids:)
          ids.map { |id| BUNDLES.find { _1[:id] == id } }
        end

        field :bundles_split, [Split, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def bundles_split(ids:)
          ids.map { |id| GIZMOS.find { _1[:id] == id } }
        end
      end

      TYPES = {
        "Product" => Product,
        "Bundle" => Bundle,
        "Gizmo" => Gizmo,
      }.freeze

      def self.resolve_type(_type, obj, _ctx)
        TYPES.fetch(obj[:__typename])
      end

      query Query
    end
  end
end
