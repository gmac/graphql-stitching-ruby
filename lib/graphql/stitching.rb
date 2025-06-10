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

      attr_writer :stitch_directive

      # Name of the directive used to denote member visibilities.
      # @returns [String] name of the visibility directive.
      def visibility_directive
        @visibility_directive ||= "visibility"
      end

      attr_writer :visibility_directive

      # Name of the directive used to denote member authorizations.
      # @returns [String] name of the authorization directive.
      def authorization_directive
        @authorization_directive ||= "authorization"
      end

      attr_writer :authorization_directive

      MIN_VISIBILITY_VERSION = "2.5.3"

      # @returns Boolean true if GraphQL::Schema::Visibility is fully supported
      def supports_visibility?
        return @supports_visibility if defined?(@supports_visibility)

        # Requires `Visibility` (v2.4) with nil profile support (v2.5.3)
        @supports_visibility = Gem::Version.new(GraphQL::VERSION) >= Gem::Version.new(MIN_VISIBILITY_VERSION)
      end
    end
  end
end

require_relative "stitching/formatter"
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
