class SubscriptionsSchema < GraphQL::Schema
  class StitchedActionCableSubscriptions < GraphQL::Subscriptions::ActionCableSubscriptions
    def execute_update(subscription_id, event, object)
      result = super(subscription_id, event, object)
      result.context[:stitch_subscription_update]&.call(result)
      result
    end
  end

  class Post < GraphQL::Schema::Object
    field :id, ID, null: false
  end

  class Comment < GraphQL::Schema::Object
    field :id, ID, null: false
  end

  class CommentAddedToPost < GraphQL::Schema::Subscription
    argument :post_id, ID, required: true
    field :post, Post, null: false
    field :comment, Comment, null: true

    def subscribe(post_id:)
      {
        post: { id: post_id },
        comment: nil,
      }
    end

    def update(post_id:)
      {
        post: { id: post_id },
        comment: object,
      }
    end
  end

  class SubscriptionType < GraphQL::Schema::Object
    field :comment_added_to_post, subscription: CommentAddedToPost
  end

  class QueryType < GraphQL::Schema::Object
    field :ping, String

    def ping
      "PONG"
    end
  end

  use StitchedActionCableSubscriptions

  subscription SubscriptionType
  query QueryType
end
