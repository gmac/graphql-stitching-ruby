# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module GraphQL
  module Stitching
    class RemoteClient
      def initialize(url:, headers:{})
        @url = url
        @headers = headers
      end

      def call(location, document, variables)
        response = Net::HTTP.post(
          URI(@url),
          { "query" => document, "variables" => variables }.to_json,
          { "Content-Type" => "application/json" }.merge!(@headers)
        )
        JSON.parse(response.body)
      end
    end
  end
end
