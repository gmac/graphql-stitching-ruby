# frozen_string_literal: true

module Schemas
  module Federation
    class StitchField < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    class FederationKey < GraphQL::Schema::Directive
      graphql_name "key"
      locations OBJECT
      argument :fields, String
      repeatable true
    end

    SPROCKETS = [
      { id: "1", cogs: 23, diameter: 77, __typename: "Sprocket" },
      { id: "2", cogs: 14, diameter: 20, __typename: "Sprocket" },
      { id: "3", cogs: 7, diameter: 12, __typename: "Sprocket" },
    ].freeze

    GADGETS = [
      { id: "1", name: "Fizz", weight: 10, __typename: "Gadget" },
      { id: "2", name: "Bang", weight: 42, __typename: "Gadget" },
    ].freeze

    WIDGETS = [
      { upc: "1", model: "Basic", megahertz: 3, sprockets: SPROCKETS[0..1], __typename: "Widget" },
      { upc: "2", model: "Advanced", megahertz: 6, sprockets: SPROCKETS[1..1], __typename: "Widget" },
      { upc: "3", model: "Delux", megahertz: 12, sprockets: SPROCKETS[1..-1], __typename: "Widget" },
    ].freeze

    # Federation

    class Federation1 < GraphQL::Schema
      class Sprocket < GraphQL::Schema::Object
        directive FederationKey, fields: "id"
        field :id, ID, null: false
        field :cogs, Int, null: false
      end

      class Gadget < GraphQL::Schema::Object
        directive FederationKey, fields: "id"
        field :id, ID, null: false
        field :name, String, null: false
      end

      class Widget < GraphQL::Schema::Object
        directive FederationKey, fields: "upc"
        field :upc, ID, null: false
        field :model, String, null: false
        field :sprockets, [Sprocket], null: false
      end

      class Entity < GraphQL::Schema::Union
        graphql_name "_Entity"
        possible_types Gadget, Sprocket, Widget
      end

      class Any < GraphQL::Schema::Scalar
        graphql_name "_Any"
      end

      class Query < GraphQL::Schema::Object
        field :_entities, [Entity, null: true], null: false do
          argument :representations, [Any], required: true
        end

        def _entities(representations:)
          representations.map do |representation|
            case representation["__typename"]
            when "Gadget"
              GADGETS.find { _1[:id] == representation["id"] }
            when "Sprocket"
              SPROCKETS.find { _1[:id] == representation["id"] }
            when "Widget"
              WIDGETS.find { _1[:upc] == representation["upc"] }
            end
          end
        end
      end

      def self.resolve_type(_type, obj, _ctx)
        {
          "Gadget" => Gadget,
          "Sprocket" => Sprocket,
          "Widget" => Widget,
        }.fetch(obj[:__typename])
      end

      query Query
    end

    class Federation2 < GraphQL::Schema
      class Sprocket < GraphQL::Schema::Object
        directive FederationKey, fields: "id"
        field :id, ID, null: false
        field :diameter, Int, null: false
      end

      class Gadget < GraphQL::Schema::Object
        directive FederationKey, fields: "id"
        field :id, ID, null: false
        field :weight, Int, null: false
      end

      class Widget < GraphQL::Schema::Object
        directive FederationKey, fields: "upc"
        field :upc, ID, null: false
        field :megahertz, Int, null: false
      end

      class Entity < GraphQL::Schema::Union
        graphql_name "_Entity"
        possible_types Gadget, Sprocket, Widget
      end

      class Any < GraphQL::Schema::Scalar
        graphql_name "_Any"
      end

      class Query < GraphQL::Schema::Object
        field :gadget, Gadget, null: false
        field :widget, Widget, null: false
        field :_entities, [Entity, null: true], null: false do
          argument :representations, [Any], required: true
        end

        def gadget
          GADGETS.first
        end

        def widget
          WIDGETS.first
        end

        def _entities(representations:)
          representations.map do |representation|
            case representation["__typename"]
            when "Gadget"
              GADGETS.find { _1[:id] == representation["id"] }
            when "Sprocket"
              SPROCKETS.find { _1[:id] == representation["id"] }
            when "Widget"
              WIDGETS.find { _1[:upc] == representation["upc"] }
            end
          end
        end
      end

      def self.resolve_type(_type, obj, _ctx)
        {
          "Gadget" => Gadget,
          "Sprocket" => Sprocket,
          "Widget" => Widget,
        }.fetch(obj[:__typename])
      end

      query Query
    end

    class Stitching < GraphQL::Schema
      class Sprocket < GraphQL::Schema::Object
        field :id, ID, null: false
        field :diameter, Int, null: false
      end

      class Gadget < GraphQL::Schema::Object
        field :id, ID, null: false
        field :weight, Int, null: false
      end

      class Widget < GraphQL::Schema::Object
        field :upc, ID, null: false
        field :megahertz, Int, null: false
      end

      class Query < GraphQL::Schema::Object
        field :gadgets, [Gadget, null: true], null: false do
          directive StitchField, key: "id"
          argument :ids, [ID], required: true
        end

        field :sprockets, [Sprocket, null: true], null: false do
          directive StitchField, key: "id"
          argument :ids, [ID], required: true
        end

        field :widgets, [Widget, null: true], null: false do
          directive StitchField, key: "upc"
          argument :upcs, [ID], required: true
        end

        def gadgets(ids:)
          ids.map { |id| GADGETS.find { _1[:id] == id } }
        end

        def sprockets(ids:)
          ids.map { |id| SPROCKETS.find { _1[:id] == id } }
        end

        def widgets(upcs:)
          upcs.map { |upc| WIDGETS.find { _1[:upc] == upc } }
        end
      end

      query Query
    end
  end
end
