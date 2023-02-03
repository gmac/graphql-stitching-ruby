# frozen_string_literal: true

module Schemas
  module Interfaces
    class Boundary < GraphQL::Schema::Directive
      graphql_name "boundary"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    PRODUCTS = [
      { id: '1', name: 'iPhone', price: 699.99 },
      { id: '2', name: 'Apple Watch', price: 399.99 },
      { id: '3', name: 'Super Baking Cookbook', price: 15.99 },
      { id: '4', name: 'Best Selling Novel', price: 7.99 },
      { id: '5', name: 'iOS Survival Guide', price: 24.99 },
    ].freeze

    BUNDLES = [
      { id: '1', name: 'Apple Gear', price: 999.99, product_ids: ['1', '2'], __typename: 'Bundle' },
      { id: '2', name: 'Epicures', price: 20.99, product_ids: ['3', '4'], __typename: 'Bundle' },
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

      class Query < GraphQL::Schema::Object
        field :products, [Product, null: true], null: false do
          argument :ids, [ID], required: true
        end

        def product(ids:)
          ids.map { |id| PRODUCTS.find { _1[:id] == id } }
        end

        field :buyables, [Buyable, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def buyables(ids:)
          ids.map { |id| PRODUCTS.find { _1[:id] == id } }
        end
      end

      def self.resolve_type(_type, _obj, _ctx)
        Product
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

      class Query < GraphQL::Schema::Object
        field :bundles, [Bundle, null: true], null: false do
          argument :ids, [ID], required: true
        end

        def bundles(ids:)
          ids.map { |id| BUNDLES.find { _1[:id] == id } }
        end

        field :buyables, [Buyable, null: true], null: false do
          directive Boundary, key: "id"
          argument :ids, [ID], required: true
        end

        def buyables(ids:)
          ids.map { |id| BUNDLES.find { _1[:id] == id } }
        end
      end

      TYPES = {
        "Product" => Product,
        "Bundle" => Bundle,
      }.freeze

      def self.resolve_type(_type, obj, _ctx)
        TYPES.fetch(obj[:__typename])
      end

      query Query
    end
  end
end
