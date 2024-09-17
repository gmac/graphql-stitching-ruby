# frozen_string_literal: true

module Schemas
  module Shopify
    class StitchingResolver < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    VARIANTS = [
      { id: '1', title: 'a', price: 23 },
      { id: '2', title: 'b', price: 12 },
      { id: '3', title: 'c', price: 4},
      { id: '4', title: 'd', price: 23 },
      { id: '5', title: 'e', price: 77 },
      { id: '6', title: 'f', price: 9},
      { id: '7', title: 'g', price: 106 },
      { id: '8', title: 'h', price: 47 },
      { id: '9', title: 'i', price: 39 },
      { id: '10', title: 'j', price: 82 },
      { id: '11', title: 'k', price: 26 },
      { id: '12', title: 'l', price: 451 },
      { id: '13', title: 'm', price: 92 },
      { id: '14', title: 'n', price: 11 },
      { id: '15', title: 'o', price: 1 },
      { id: '16', title: 'p', price: 22 },
    ].each_with_object({}) { |i, o| o[i[:id]] = i }

    COLLECTIONS = [
      { id: '1', title: 'Featured' },
      { id: '2', title: 'Up and Coming' },
      { id: '3', title: 'Seasonal' },
    ].each_with_object({}) { |i, o| o[i[:id]] = i }

    PRODUCTS = [
      {
        id: '1',
        title: 'Mercury',
        variants: [1, 2].map(&:to_s),
        collections: [1, 2].map(&:to_s),
      },
      {
        id: '2',
        title: 'Venus',
        variants: [3, 4].map(&:to_s),
        collections: [3, 1].map(&:to_s),
      },
      {
        id: '3',
        title: 'Earth',
        variants: [5, 6].map(&:to_s),
        collections: [1, 2].map(&:to_s),
      },
      {
        id: '4',
        title: 'Mars',
        variants: [7, 8].map(&:to_s),
        collections: [3, 2].map(&:to_s),
      },
      {
        id: '5',
        title: 'Jupiter',
        variants: [9, 10].map(&:to_s),
        collections: [1, 3].map(&:to_s),
      },
      {
        id: '6',
        title: 'Saturn',
        variants: [11, 12].map(&:to_s),
        collections: [1, 2].map(&:to_s),
      },
      {
        id: '7',
        title: 'Neptune',
        variants: [13, 14].map(&:to_s),
        collections: [3, 1].map(&:to_s),
      },
      {
        id: '8',
        title: 'Uranus',
        variants: [15, 16].map(&:to_s),
        collections: [1, 3].map(&:to_s),
      },
    ].each_with_object({}) { |i, o| o[i[:id]] = i }

    class ProductsService < GraphQL::Schema
      class Variant < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class Collection < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class Product < GraphQL::Schema::Object
        field :id, ID, null: false
        field :title, String, null: false

        field :variants, [Variant], null: false
        def variants
          object[:variants].map { |id| { id: id } }
        end

        field :collections, [Collection], null: false
        def collections
          object[:collections].map { |id| { id: id } }
        end
      end

      class Query < GraphQL::Schema::Object
        field :products, [Product, null: true], null: false do
          directive StitchingResolver, key: "id"
          argument :ids, [ID, null: false], required: true
        end

        def products(ids:)
          ids.map { |id| PRODUCTS[id] }
        end
      end

      query Query
    end

    class CollectionsService < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class Collection < GraphQL::Schema::Object
        field :id, ID, null: false
        field :title, String, null: false
        field :products, [Product], null: false

        def products
          PRODUCTS.values.select { _1[:collections].include?(object[:id]) }
        end
      end

      class Query < GraphQL::Schema::Object
        field :collections, [Collection, null: true], null: false do
          directive StitchingResolver, key: "id"
          argument :ids, [ID, null: false], required: true
        end

        def collections(ids:)
          ids.map { |id| COLLECTIONS[id] }
        end
      end

      query Query
    end

    class VariantsService < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class Variant < GraphQL::Schema::Object
        field :id, ID, null: false
        field :title, String, null: false
        field :product, Product, null: false

        def product
          PRODUCTS.values.find { _1[:variants].include?(object[:id]) }
        end
      end

      class Query < GraphQL::Schema::Object
        field :variants, [Variant, null: true], null: false do
          directive StitchingResolver, key: "id"
          argument :ids, [ID, null: false], required: true
        end

        def variants(ids:)
          ids.map { |id| VARIANTS[id] }
        end
      end

      query Query
    end
  end
end
