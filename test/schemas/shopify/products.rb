# frozen_string_literal: true
require_relative "./_common"
require_relative "./_service"

module Schemas
  module Shopify
    class ProductsScope < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :id, ID, null: false
        field :title, String, null: false
      end

      class Collection < GraphQL::Schema::Object
        field :id, ID, null: false
        field :products, [Product], null: false

        def products
          ShopifyService.products_for_collection(object[:id] || object["id"])
        end
      end

      class Entity < GraphQL::Schema::Union
        possible_types Collection, Product

        def self.resolve_type(object, _ctx)
          { "Collection" => Collection, "Product" => Product }[object["__typename"]]
        end
      end

      class Query < GraphQL::Schema::Object
        field :products, [Product, null: true], null: false do
          directive StitchingResolver, key: "id"
          argument :ids, [ID, null: false], required: true
        end

        def products(ids:)
          ShopifyService.products_by_ids(ids)
        end

        field :_entities, [Entity, null: true], null: false do
          directive StitchingResolver, key: "id"
          argument :ids, [ID, null: false], required: true
        end

        def _entities(ids:)
          ids.map do |id|
            # bug in resolver selection... products should load through the main endpoint
            obj = id.start_with?("Product") ? ShopifyService.products_by_ids([id]).first : { "id" => id }
            obj["__typename"] = id.split("/").first
            obj
          end
        end
      end

      query Query
    end
  end
end
