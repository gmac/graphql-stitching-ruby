# frozen_string_literal: true

module Schemas
  module Subscriptions
    class SubscriptionSchema < GraphQL::Schema
      class Product < GraphQL::Schema::Object
        field :upc, ID, null: false
      end

      class Manufacturer < GraphQL::Schema::Object
        field :id, ID, null: false
      end

      class UpdateToProduct < GraphQL::Schema::Subscription
        argument :upc, ID, required: true
        field :product, Product, null: false
        field :manufacturer, Manufacturer, null: true

        def subscribe(upc:)
          { product: { upc: upc }, manufacturer: nil }
        end

        def update(upc:)
          { product: { upc: upc }, manufacturer: object }
        end
      end

      class SubscriptionType < GraphQL::Schema::Object
        field :update_to_product, subscription: UpdateToProduct
      end

      class QueryType < GraphQL::Schema::Object
        field :ping, String
      end

      query QueryType
      subscription SubscriptionType
    end
  end
end
