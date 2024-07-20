# Subscriptions example

This example demonstrates stitching subscriptions in a small Rails application. No database required, just bundle-install and try running it:

```shell
cd examples/subscriptions
bundle install
bin/rails s
```

Then visit the GraphiQL client running at [`http://localhost:3000`](http://localhost:3000) and try subscribing:

```graphql
subscription SubscribeToComments {
  commentAddedToPost(postId: "1") {
    post { 
      id 
      title
      comments {
        id
        message
      }
    }
    comment { 
      id
      message
    }
  }
}
```

Upon running that subscription, you'll recieve an initial payload for the subscribe event that stitches post data from another schema. Now try triggering events by hitting this URL in another browser window:

```
http://localhost:3000/graphql/event
```

Each refresh of the above URL will add a comment and trigger a subscription event. Assuming you're subscribed, you should see comment activity appear in the GraphiQL output. Again, these update events are stitched to enrich the basic subscription payload with additional data from another schema.
