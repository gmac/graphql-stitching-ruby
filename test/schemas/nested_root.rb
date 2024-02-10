# frozen_string_literal: true

module Schemas
  module NestedRoot
    class Alpha < GraphQL::Schema
      class Query < GraphQL::Schema::Object
        field :apple, String, null: false
        field :error_a, String, null: false

        def apple
          "red"
        end

        def error_a
          raise GraphQL::ExecutionError.new("a")
        end
      end

      class Thing < GraphQL::Schema::Object
        field :query, Query, null: false

        def query
          {}
        end
      end

      class Mutation < GraphQL::Schema::Object
        field :do_stuff, Query, null: false

        def do_stuff
          {}
        end

        field :do_thing, Thing, null: false

        def do_thing
          {}
        end

        field :do_things, [Thing], null: false

        def do_things
          [{}, {}]
        end
      end

      query Query
      mutation Mutation
    end

    class Bravo < GraphQL::Schema
      class Query < GraphQL::Schema::Object
        field :banana, String, null: false
        field :error_b, String, null: false

        def banana
          "yellow"
        end

        def error_b
          raise GraphQL::ExecutionError.new("b")
        end
      end

      query Query
    end
  end
end
