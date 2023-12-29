# frozen_string_literal: true

require 'action_dispatch'
require 'apollo_upload_server/graphql_data_builder'
require 'apollo_upload_server/upload'

# ApolloUploadServer middleware only modifies Rails request params;
# for simple Rack apps we need to extract the behavior.
def apollo_upload_server_middleware_params(env)
  req = ActionDispatch::Request.new(env)
  if env['CONTENT_TYPE'].to_s.include?('multipart/form-data')
    ApolloUploadServer::GraphQLDataBuilder.new(strict_mode: true).call(req.params)
  else
    req.params
  end
end

# Gateway local schema
class GatewaySchema < GraphQL::Schema
  class Query < GraphQL::Schema::Object
    field :gateway, Boolean, null: false

    def gateway
      true
    end
  end

  class Mutation < GraphQL::Schema::Object
    field :gateway, Boolean, null: false

    def gateway
      true
    end
  end

  query Query
  mutation Mutation
end

# Remote local schema, with file upload
class RemoteSchema < GraphQL::Schema
  class Query < GraphQL::Schema::Object
    field :remote, Boolean, null: false

    def remote
      true
    end
  end

  class Mutation < GraphQL::Schema::Object
    field :upload, String, null: true do
      argument :file, ApolloUploadServer::Upload, required: true
    end

    def upload(file:)
      file.read
    end
  end

  query Query
  mutation Mutation
end
