class EntitiesSchema < GraphQL::Schema
  class StitchingResolver < GraphQL::Schema::Directive
    graphql_name "stitch"
    locations FIELD_DEFINITION
    argument :key, String, required: true
    argument :arguments, String, required: false
    repeatable true
  end

  class Comment < GraphQL::Schema::Object
    field :id, ID, null: false
    field :message, String, null: false
  end

  class Post < GraphQL::Schema::Object
    field :id, ID, null: false
    field :title, String, null: false
    field :comments, [Comment, null: false], null: false
  end

  class QueryType < GraphQL::Schema::Object
    field :posts, [Post, null: true] do
      directive StitchingResolver, key: "id"
      argument :ids, [ID], required: true
    end

    def posts(ids:)
      ids.map { Repository.post(_1) }
    end

    field :comments, [Comment, null: true] do
      directive StitchingResolver, key: "id"
      argument :ids, [ID], required: true
    end

    def comments(ids:)
      ids.map { Repository.comment(_1) }
    end
  end

  query QueryType
end
