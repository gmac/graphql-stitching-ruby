class GraphqlController < ActionController::Base
  skip_before_action :verify_authenticity_token
  layout false

  def client
  end

  def execute
    result = StitchedSchema.execute(
      params[:query],
      variables: ensure_hash(params[:variables]), 
      context: {}, 
      operation_name: params[:operationName],
    )

    render json: result
  end

  COMMENTS = ["Great", "Meh", "Terrible"].freeze

  def event
    comment = Repository.add_comment("1", COMMENTS.sample)
    render json: comment
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
