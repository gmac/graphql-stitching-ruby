class GraphqlChannel < ActionCable::Channel::Base
  def subscribed
    @subscription_ids = []
  end

  def execute(data)
    result = StitchedSchema.execute(
      data["query"],
      context: { channel: self },
      variables: ensure_hash(data["variables"]),
      operation_name: data["operationName"],
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
      SubscriptionsSchema.subscriptions.delete_subscription(sid)
    }
  end

  private

  def ensure_hash(ambiguous_param)
    case ambiguous_param
    when String
      if ambiguous_param.present?
        ensure_hash(JSON.parse(ambiguous_param))
      else
        {}
      end
    when Hash, ActionController::Parameters
      ambiguous_param
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{ambiguous_param}"
    end
  end
end
