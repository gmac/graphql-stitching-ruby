# frozen_string_literal: true
require_relative "./_common"
require_relative "./_service"

module Schemas
  module Shopify
    class CollectionsScope < GraphQL::Schema
      class Collection < GraphQL::Schema::Object
        field :id, ID, null: false
        field :title, String, null: false
      end

      class Product < GraphQL::Schema::Object
        field :id, ID, null: false
        field :collections, [Collection], null: false

        def collections
          ShopifyService.collections_for_product(object[:id] || object["id"])
        end
      end

      class Entity < GraphQL::Schema::Union
        possible_types Product
      end

      class Query < GraphQL::Schema::Object
        field :collections, [Collection, null: true], null: false do
          directive StitchingResolver, key: "id"
          argument :ids, [ID, null: false], required: true
        end

        def collections(ids:)
          ShopifyService.collections_by_ids(ids)
        end

        field :_entities, [Entity, null: true], null: false do
          directive StitchingResolver, key: "id"
          argument :ids, [ID, null: false], required: true
        end

        def _entities(ids:)
          ids.map do |id|
            { "id" => id, "__typename" => id.split("/").first }
          end
        end
      end

      def self.resolve_type(_type, object, _ctx)
        { "Product" => Product }[object["__typename"]]
      end

      query Query
    end
  end
end
