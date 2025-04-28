# frozen_string_literal: true

module Schemas
  module MultipleKeys
    PRODUCTS = [
      { id: '1', upc: 'xyz', name: 'iPhone', location: 'Toronto', edition: 'Spring' },
    ].freeze

    # Storefronts

    class Storefronts < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :id, ID, null: false
        field :location, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :storefronts_product_by_id, Product, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def storefronts_product_by_id(id:)
          PRODUCTS.find { _1[:id] == id }
        end
      end

      query Query
    end

    # Products

    class Products < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :id, ID, null: false
        field :upc, ID, null: false
        field :name, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :products_product_by_id, Product, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :id, ID, required: true
        end

        def products_product_by_id(id:)
          PRODUCTS.find { _1[:id] == id }
        end

        field :products_product_by_upc, Product, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "upc"
          argument :upc, ID, required: true
        end

        def products_product_by_upc(upc:)
          PRODUCTS.find { _1[:upc] == upc }
        end
      end

      query Query
    end

    # Catelogs

    class Catelogs < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :upc, ID, null: false
        field :edition, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :catalogs_product_by_upc, Product, null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "upc"
          argument :upc, ID, required: true
        end

        def catalogs_product_by_upc(upc:)
          PRODUCTS.find { _1[:upc] == upc }
        end
      end

      query Query
    end
  end
end
