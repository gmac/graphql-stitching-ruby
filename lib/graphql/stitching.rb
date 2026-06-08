# frozen_string_literal: true
# typed: true

require "graphql"

module GraphQL
  module Stitching
    QUERY_OP = "query".freeze #: String

    MUTATION_OP = "mutation".freeze #: String

    SUBSCRIPTION_OP = "subscription".freeze #: String

    TYPENAME = "__typename".freeze #: String

    EMPTY_OBJECT = {}.freeze #: Hash[untyped, untyped]

    EMPTY_ARRAY = [].freeze #: Array[untyped]

    class StitchingError < StandardError; end
    class CompositionError < StitchingError; end
    class ValidationError < CompositionError; end
    class DocumentError < StandardError
      #: (String element) -> void
      def initialize(element)
        super("Invalid #{element} encountered in document")
      end
    end

    MIN_VISIBILITY_VERSION = "2.5.3".freeze #: String

    class << self
      # @rbs!
      #   @digest: ^(String) -> String
      #   @stitch_directive: String
      #   @visibility_directive: String
      #   @supports_visibility: bool

      #: ?{ (String) -> String } -> ^(String) -> String
      def digest(&block)
        if block_given?
          @digest = block
        else
          @digest ||= ->(str) { Digest::SHA2.hexdigest(str) }
        end
      end

      #: -> String
      def stitch_directive
        @stitch_directive ||= "stitch".freeze
      end

      #: String
      attr_writer :stitch_directive

      #: -> String
      def visibility_directive
        @visibility_directive ||= "visibility".freeze
      end

      #: String
      attr_writer :visibility_directive

      #: -> bool
      def supports_visibility?
        return @supports_visibility if defined?(@supports_visibility)

        # Requires `Visibility` (v2.4) with nil profile support (v2.5.3)
        @supports_visibility = Gem::Version.new(GraphQL::VERSION) >= Gem::Version.new(MIN_VISIBILITY_VERSION)
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
