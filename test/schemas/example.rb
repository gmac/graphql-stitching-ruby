# frozen_string_literal: true

module Schemas
  module Example
    PRODUCTS = [
      { upc: '1', name: 'iPhone', price: 699.99, manufacturer_id: '1' },
      { upc: '2', name: 'Apple Watch', price: 399.99, manufacturer_id: '1' },
      { upc: '3', name: 'Super Baking Cookbook', price: 15.99, manufacturer_id: '2' },
      { upc: '4', name: 'Best Selling Novel', price: 7.99, manufacturer_id: '2' },
      { upc: '5', name: 'iOS Survival Guide', price: 24.99, manufacturer_id: '1' },
      { upc: '6', name: 'Unicorn', price: 1.11, manufacturer_id: '3' },
    ].freeze

    STOREFRONTS = [
      { id: '1', name: 'eShoppe', product_upcs: ['1', '2'] },
      { id: '2', name: 'BestBooks Online', product_upcs: ['3', '4', '5'] },
      { id: '3', name: 'Magic Shoppe', product_upcs: ['6'] },
    ].freeze

    MANUFACTURERS = [
      { id: '1', name: 'Apple', address: '123 Main' },
      { id: '2', name: 'Macmillan', address: '456 Market' },
      { id: '3', name: 'Narnia', address: "123" }, # invalid address
    ].freeze

    # Products

    class Products < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :upc, ID, null: false
        field :name, String, null: false
        field :price, Float, null: false
        field :manufacturer, "Schemas::Example::Products::Manufacturer", null: true
        field :pages, Integer, null: true

        def manufacturer
          { id: object[:manufacturer_id] }
        end
      end

      class Manufacturer < GraphQL::Schema::Object
        field :id, ID, null: false
        field :products, [Product], null: false

        def products
          PRODUCTS.select { _1[:manufacturer_id] == object[:id] }
        end
      end

      class RootQuery < GraphQL::Schema::Object
        field :product, Product, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "upc"
          argument :upc, ID, required: true
        end

        def product(upc:)
          PRODUCTS.find { _1[:upc] == upc }
        end

        field :manufacturer, Manufacturer, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def manufacturer(id:)
          MANUFACTURERS.find { _1[:id] == id }
        end
      end

      query RootQuery
    end

    # Storefronts

    class Storefronts < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :upc, ID, null: false
      end

      class Storefront < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
        field :products, [Product], null: false do
          argument :first, Integer, required: false
        end

        def products(first: nil)
          fks = object[:product_upcs]
          fks.take(first) if first
          fks.map { |upc| { upc: upc } }
        end
      end

      class Query < GraphQL::Schema::Object
        field :storefront, Storefront, null: true do
          argument :id, ID, required: true
        end

        def storefront(id:)
          STOREFRONTS.find { _1[:id] == id }
        end
      end

      query Query
    end

    # Manufacturers

    class Manufacturers < GraphQL::Schema
      class Manufacturer < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
        field :address, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :manufacturer, Manufacturer, null: true do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def manufacturer(id:)
          MANUFACTURERS.find { _1[:id] == id }
        end
      end

      query Query
    end
  end
end
