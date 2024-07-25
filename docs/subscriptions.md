## Stitching subscriptions

Stitching is an interesting prospect for subscriptions because socket-based interactions can be isolated to their own schema/server with very little implementation beyond resolving entity keys. Then, entity data can be stitched onto subscription payloads from other locations.

### Composing a subscriptions schema

For simplicity, subscription resolvers should exist together in a single schema (multiple schemas with subscriptions probably aren't worth the confusion). This subscriptions schema may provide basic entity types that will merge with other locations. For example, here's a bare-bones subscriptions schema:

```ruby
class SubscriptionSchema < GraphQL::Schema
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
      { post: { id: post_id }, comment: nil }
    end

    def update(post_id:)
      { post: { id: post_id }, comment: object }
    end
  end

  class SubscriptionType < GraphQL::Schema::Object
    field :comment_added_to_post, subscription: CommentAddedToPost
  end

  use GraphQL::Subscriptions::ActionCableSubscriptions
  subscription SubscriptionType
end
```

The above subscriptions schema can compose with other locations, such as the following that provides full entity types:

```ruby
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
      Post.where(id: ids)
    end

    field :comments, [Comment, null: true] do
      directive StitchingResolver, key: "id"
      argument :ids, [ID], required: true
    end

    def comments(ids:)
      Comment.where(id: ids)
    end
  end

  query QueryType
end
```

These schemas can be composed as normal into a stitching client. The subscriptions schema must be locally-executable while other entity schema(s) may be served from anywhere:

```ruby
StitchedSchema = GraphQL::Stitching::Client.new(locations: {
  subscriptions: {
    schema: SubscriptionSchema, # << locally executable!
  },
  entities: {
    schema: GraphQL::Schema.from_definition(entities_schema_sdl),
    executable: GraphQL::Stitching::HttpExecutable.new("http://localhost:3001"),
  },
})
```

### Serving stitched subscriptions

Once you've stitched a schema with subscriptions, it gets called as part of three workflows:

1. Controller - handles normal query and mutation requests recieved via HTTP.
2. Channel - handles subscription-create requests recieved through a socket connection.
3. Plugin – handles subscription-update events pushed to the socket connection.

#### Controller

A controller will recieve basic query and mutation requests sent over HTTP, including introspection requests. Fulfill these using the stitched schema client.

```ruby
class GraphqlController < ApplicationController
  skip_before_action :verify_authenticity_token
  layout false

  def execute
    result = StitchedSchema.execute(
      params[:query],
      context: {}, 
      variables: params[:variables],
      operation_name: params[:operationName],
    )

    render json: result
  end
end
```

#### Channel

A channel handles subscription requests initiated via websocket connection. This mostly follows the [GraphQL Ruby documentation example](https://graphql-ruby.org/api-doc/2.3.9/GraphQL/Subscriptions/ActionCableSubscriptions), except that `execute` uses the stitched schema client while `unsubscribed` uses the subscriptions subschema directly:

```ruby
class GraphqlChannel < ApplicationCable::Channel
  def subscribed
    @subscription_ids = []
  end

  def execute(params)
    result = StitchedSchema.execute(
      params["query"],
      context: { channel: self },
      variables: params["variables"],
      operation_name: params["operationName"]
    )

    payload = {
      result: result.to_h,
      more: result.subscription?,
    }

    if result.context[:subscription_id]
      @subscription_ids << result.context[:subscription_id]
    end

    transmit(payload)
  end

  def unsubscribed
    @subscription_ids.each { |sid|
      # Go directly through the subscriptions subschema 
      # when managing/triggering subscriptions:
      SubscriptionSchema.subscriptions.delete_subscription(sid)
    }
  end
end
```

What happens behind the scenes here is that stitching filters the `execute` request down to just subscription selections, and passes those through to the subscriptions subschema where they register an event binding. The subscriber response gets stitched while passing back up through the stitching client.

#### Plugin

Lastly, update events trigger with the filtered subscriptions selection, so must get stitched before transmitting. The stitching client adds an update handler into request context for this purpose. A small patch to the subscriptions plugin class can call this handler on update event payloads before transmitting them:

```ruby
class StitchedActionCableSubscriptions < GraphQL::Subscriptions::ActionCableSubscriptions
  def execute_update(subscription_id, event, object)
    super(subscription_id, event, object).tap do |result|
      result.context[:stitch_subscription_update]&.call(result)
    end
  end
end

class SubscriptionSchema
  # switch the plugin on the subscriptions schema to use the patched class... 
  use StitchedActionCableSubscriptions
end
```

### Triggering subscriptions

Subscription update events are triggered as normal directly through the subscriptions subschema:

```ruby
class Comment < ApplicationRecord
  after_create :trigger_subscriptions
  
  def trigger_subscriptions
    SubscriptionsSchema.subscriptions.trigger(:comment_added_to_post, { post_id: post_id }, self)
  end
end
```
