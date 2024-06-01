# frozen_string_literal: true

module Schemas
  module Mutations
    class Resolver < GraphQL::Schema::Directive
      graphql_name "stitch"
      locations FIELD_DEFINITION
      argument :key, String
      repeatable true
    end

    RECORDS = []

    class << self
      def reset
        while RECORDS.length > 0
          RECORDS.pop
        end
      end

      def creation_order
        RECORDS.map { _1[:id] }
      end
    end

    # Mutations A

    class MutationsA < GraphQL::Schema
      class Record < GraphQL::Schema::Object
        field :id, ID, null: false
        field :a, String, null: false
        field :via, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :recordA, Record, null: true do
          directive Resolver, key: "id"
          argument :id, ID, required: true
        end

        def recordA(id:)
          RECORDS.find { _1[:id] == id }
        end
      end

      class Mutation < GraphQL::Schema::Object
        field :addViaA, Record, null: false

        def addViaA
          id = RECORDS.length + 1
          RECORDS << { id: id.to_s, via: "A", a: "A#{id}", b: "B#{id}" }
          RECORDS.last
        end
      end

      query Query
      mutation Mutation
    end

    # Mutations B

    class MutationsB < GraphQL::Schema
      class Record < GraphQL::Schema::Object
        field :id, ID, null: false
        field :b, String, null: false
        field :via, String, null: false
      end

      class Query < GraphQL::Schema::Object
        field :recordB, Record, null: true do
          directive Resolver, key: "id"
          argument :id, ID, required: true
        end

        def recordB(id:)
          RECORDS.find { _1[:id] == id }
        end
      end

      class Mutation < GraphQL::Schema::Object
        field :addViaB, Record, null: false

        def addViaB
          id = RECORDS.length + 1
          RECORDS << { id: id.to_s, via: "B", a: "A#{id}", b: "B#{id}" }
          RECORDS.last
        end
      end

      query Query
      mutation Mutation
    end
  end
end
