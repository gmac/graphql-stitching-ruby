# frozen_string_literal: true

require "graphql"

module GraphQL
  module Stitching
    # scope name of query operations.
    QUERY_OP = "query"
    
    # scope name of mutation operations.
    MUTATION_OP = "mutation"
    
    # scope name of subscription operations.
    SUBSCRIPTION_OP = "subscription"
    
    # introspection typename field.
    TYPENAME = "__typename"

    # @api private
    EMPTY_OBJECT = {}.freeze

    # @api private
    EMPTY_ARRAY = [].freeze

    class StitchingError < StandardError; end
    class CompositionError < StitchingError; end
    class ValidationError < CompositionError; end
    class DocumentError < StandardError
      def initialize(element)
        super("Invalid #{element} encountered in document")
      end
    end

    class << self
      attr_writer :stitch_directive

      # Proc used to compute digests; uses SHA2 by default.
      # @returns [Proc] proc used to compute digests.
      def digest(&block)
        if block_given?
          @digest = block
        else
          @digest ||= ->(str) { Digest::SHA2.hexdigest(str) }
        end
      end

      # Name of the directive used to mark type resolvers.
      # @returns [String] name of the type resolver directive.
      def stitch_directive
        @stitch_directive ||= "stitch"
      end
    end
  end
end

require_relative "stitching/directives"
require_relative "stitching/supergraph"
require_relative "stitching/client"
require_relative "stitching/composer"
require_relative "stitching/executor"
require_relative "stitching/http_executable"
require_relative "stitching/plan"
require_relative "stitching/planner"
require_relative "stitching/request"
require_relative "stitching/type_resolver"
require_relative "stitching/util"
require_relative "stitching/version"
