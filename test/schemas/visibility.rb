# frozen_string_literal: true

module Schemas
  module Visibility
    class Boundary < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    class Visibility < GraphQL::Schema::Directive
      graphql_name "visibility"
      locations FIELD_DEFINITION, ARGUMENT_DEFINITION, ENUM_VALUE, OBJECT
      argument :scopes, [[String]]
    end

    class Alpha < GraphQL::Schema
      class Thing < GraphQL::Schema::Object
        field :id, ID, null: false
        field :color, String, null: false do |f|
          f.directive(Visibility, scopes: [["a"], ["c"]])
        end

        field :size, Integer, null: false do |f|
          f.directive(Visibility, scopes: [["a"]])
        end
      end

      class Widget < GraphQL::Schema::Object
        directive(Visibility, scopes: [["a"]])
        field :id, ID, null: false
      end

      class Toggle < GraphQL::Schema::Enum
        value "YES"
        value "NO"
        value "MAYBE" do |v|
          v.directive(Visibility, scopes: [["a"]])
        end
      end

      class Query < GraphQL::Schema::Object
        field :thing_a, Thing, null: false do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def thing_a(id:)
          { id: id, color: "red", size: 2 }
        end

        field :widget_a, Widget, null: false

        def widget_a
          { id: 1 }
        end

        field :args, String, null: false do
          argument :id, ID, required: false do
            directive(Visibility, scopes: [["a"]])
          end
          argument :enum, Toggle, required: false
        end

        def args(id:, enum:)
          id.to_s
        end
      end

      query Query
    end

    class Bravo < GraphQL::Schema
      class Thing < GraphQL::Schema::Object
        field :id, ID, null: false
        field :color, String, null: false do |f|
          f.directive(Visibility, scopes: [["b"], ["c"]])
        end

        field :weight, Integer, null: false do |f|
          f.directive(Visibility, scopes: [["b"]])
        end
      end

      class Widget < GraphQL::Schema::Object
        directive(Visibility, scopes: [["b"]])
        field :id, ID, null: false
      end

      class Toggle < GraphQL::Schema::Enum
        value "YES"
        value "NO"
        value "MAYBE" do |v|
          v.directive(Visibility, scopes: [["b"]])
        end
      end

      class Query < GraphQL::Schema::Object
        field :thing_b, Thing, null: false do
          directive Boundary, key: "id"
          argument :id, ID, required: true
        end

        def thing_b(id:)
          { id: id, color: "red", weight: 3 }
        end

        field :widget_b, Widget, null: false

        def widget_b
          { id: 1 }
        end

        field :args, String, null: false do
          argument :id, ID, required: false do
            directive(Visibility, scopes: [["b"]])
          end
          argument :enum, Toggle, required: false
        end

        def args(id:, enum:)
          id.to_s
        end
      end

      query Query
    end
  end
end
