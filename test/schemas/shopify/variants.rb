# frozen_string_literal: true
require_relative "./_common"
require_relative "./_service"

module Schemas
  module Shopify
    class VariantsScope < GraphQL::Schema
      class Variant < GraphQL::Schema::Object
        field :id, ID, null: false
        field :title, String, null: false
        field :product, GraphQL::Schema::LateBoundType.new("Product"), null: false

        def product
          { id: object["product_id"] }
        end
      end

      class Product < GraphQL::Schema::Object
        field :id, ID, null: false
        field :variants, [Variant], null: false

        def variants
          ShopifyService.variants_for_product(object[:id] || object["id"])
        end
      end

      class Entity < GraphQL::Schema::Union
        possible_types Product
      end

      class Query < GraphQL::Schema::Object
        field :variants, [Variant, null: true], null: false do
          directive StitchingResolver, key: "id"
          argument :ids, [ID, null: false], required: true
        end

        def variants(ids:)
          ShopifyService.variants_by_ids(ids)
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
