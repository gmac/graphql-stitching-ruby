# frozen_string_literal: true

module Schemas
  module Shareables
    class Resolver < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    # ShareableA

    class ShareableA < GraphQL::Schema
      class Gizmo < GraphQL::Schema::Object
        field :a, String, null: false
        field :b, String, null: false
        field :c, String, null: false
      end

      class Gadget < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
        field :gizmo, Gizmo, null: false
        field :unique_to_a, String, null: false

        def gizmo
          { a: "apple", b: "banana", c: "coconut" }
        end
      end

      class Query < GraphQL::Schema::Object
        field :gadget_a, Gadget, null: false do
          directive Resolver, key: "id"
          argument :id, ID, required: true
        end

        def gadget_a(id:)
          { id: id, name: "A#{id}", unique_to_a: "AA" }
        end
      end

      query Query
    end

    # ShareableB

    class ShareableB < GraphQL::Schema
      class Gizmo < GraphQL::Schema::Object
        field :a, String, null: false
        field :b, String, null: false
        field :c, String, null: false
      end

      class Gadget < GraphQL::Schema::Object
        field :id, ID, null: false
        field :name, String, null: false
        field :gizmo, Gizmo, null: false
        field :unique_to_b, String, null: false

        def gizmo
          { a: "aardvark", b: "bat", c: "cat" }
        end
      end

      class Query < GraphQL::Schema::Object
        field :gadget_b, Gadget, null: false do
          directive Resolver, key: "id"
          argument :id, ID, required: true
        end

        def gadget_b(id:)
          { id: id, name: "B#{id}", unique_to_b: "BB" }
        end
      end

      query Query
    end
  end
end
