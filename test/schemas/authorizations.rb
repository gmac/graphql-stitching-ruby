# frozen_string_literal: true

module Schemas
  module Authorizations
    PRODUCTS = [
      { id: "1", name: "iPhone", price: 699.99, description: "cool" },
      { id: "2", name: "Apple Watch", price: 399.99 },
      { id: "3", name: "Super Baking Cookbook", price: 15.99 },
    ].freeze

    ORDERS = [
      { id: "1", shipping_address: "123 Main", product_id: "1", customer: { email: "pete.cat@gmail.com" } },
      { id: "2", shipping_address: "456 Market", product_id: "2", customer: { email: "grumpytoad@gmail.com" } },
    ].freeze

    class Alpha < GraphQL::Schema
      class Customer < GraphQL::Schema::Object
        directive GraphQL::Stitching::Directives::Authorization, scopes: [["customers"]]
        field :email, String, null: false
        field :phone, String, null: true
      end

      class Product < GraphQL::Schema::Object
        directive GraphQL::Stitching::Directives::Authorization, scopes: [["products"]]
        field :id, ID, null: false
        field :name, String, null: false
        field :description, String, null: true
        field :price, Float, null: false
      end

      class Order < GraphQL::Schema::Object
        directive GraphQL::Stitching::Directives::Authorization, scopes: [["orders"]]
        field :id, ID, null: false
        field :shipping_address, String, null: false
        field :product, Product, null: false
        field :customer1, Customer, null: true
        field :customer2, Customer, null: true do
          directive GraphQL::Stitching::Directives::Authorization, scopes: [["customers"]]
        end

        def product
          PRODUCTS.find { _1[:id] == object[:product_id] }
        end

        def customer1
          object[:customer]
        end

        def customer2
          object[:customer]
        end
      end

      class Query < GraphQL::Schema::Object
        field :product_a, Product, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def product_a(id:)
          PRODUCTS.find { _1[:id] == id }
        end

        field :order_a, Order, null: false do
          directive GraphQL::Stitching::Directives::Authorization, scopes: [["orders"]]
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def order_a(id:)
          ORDERS.find { _1[:id] == id }
        end
      end

      query Query
    end

    class Bravo < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :id, ID, null: false
        field :open, Boolean, null: false

        def open
          true
        end
      end

      class Order < GraphQL::Schema::Object
        field :id, ID, null: false
        field :open, Boolean, null: false

        def open
          true
        end
      end

      class Query < GraphQL::Schema::Object
        field :product_b, Product, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def product_b(id:)
          PRODUCTS.find { _1[:id] == id }
        end

        field :order_b, Order, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def order_b(id:)
          ORDERS.find { _1[:id] == id }
        end
      end

      query Query
    end
  end
end
