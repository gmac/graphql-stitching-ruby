# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module GraphQL
  module Stitching
    class HttpExecutable
      def initialize(url:, headers:{})
        @url = url
        @headers = { "Content-Type" => "application/json" }.merge!(headers)
      end

      def call(_location, document, variables, _context)
        response = Net::HTTP.post(
          URI(@url),
          JSON.generate({ "query" => document, "variables" => variables }),
          @headers,
        )
        JSON.parse(response.body)
      end
    end
  end
end
