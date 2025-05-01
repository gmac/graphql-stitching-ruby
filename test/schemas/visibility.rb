# frozen_string_literal: true

module Schemas
  module Visibility
    RECORDS = [
      { id: "1", price: 20.99, msrp: 10.99, quantity_available: 23, quantity_in_stock: 35 },
      { id: "2", price: 99.99, msrp: 69.99, quantity_available: 77, quantity_in_stock: 100 },
    ].freeze

    class PriceSchema < GraphQL::Schema
      class Sprocket < GraphQL::Schema::Object
        field :id, ID, null: false do |f|
          f.directive(GraphQL::Stitching::Directives::Visibility, profiles: [])
        end

        field :price, Float, null: false

        field :msrp, Float, null: false do |f|
          f.directive(GraphQL::Stitching::Directives::Visibility, profiles: ["private"])
        end
      end

      class Query < GraphQL::Schema::Object
        field :sprocket, Sprocket, null: true do |f|
          f.directive(GraphQL::Stitching::Directives::Stitch, key: "id")
          f.argument(:id, ID, required: true)
        end

        def sprocket(id:)
          RECORDS.find { _1[:id] == id }
        end
      end

      query Query
    end

    class InventorySchema < GraphQL::Schema
      class Sprocket < GraphQL::Schema::Object
        field :id, ID, null: false
        
        field :quantity_available, Integer, null: false

        field :quantity_in_stock, Integer, null: false do |f|
          f.directive(GraphQL::Stitching::Directives::Visibility, profiles: ["private"])
        end
      end

      class Query < GraphQL::Schema::Object
        field :sprockets, [Sprocket], null: false do |f|
          f.directive(GraphQL::Stitching::Directives::Stitch, key: "id")
          f.directive(GraphQL::Stitching::Directives::Visibility, profiles: ["private"])
          f.argument(:ids, [ID, null: false], required: true)
        end

        def sprockets(ids:)
          ids.map { |id| RECORDS.find { _1[:id] == id } }
        end
      end

      query Query
    end
  end
end
