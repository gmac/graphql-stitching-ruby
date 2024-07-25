require_relative "../../../../lib/graphql/stitching"

StitchedSchema = GraphQL::Stitching::Client.new(locations: {
  entities: {
    schema: EntitiesSchema,
  },
  subscriptions: {
    schema: SubscriptionsSchema,
  },
})
