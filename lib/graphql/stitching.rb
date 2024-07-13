# frozen_string_literal: true

require "graphql"

module GraphQL
  module Stitching
    # @api private
    EMPTY_OBJECT = {}.freeze

    # @api private
    EMPTY_ARRAY = [].freeze

    class StitchingError < StandardError; end
    class CompositionError < StitchingError; end
    class ValidationError < CompositionError; end

    class << self
      def stitch_directive
        @stitch_directive ||= "stitch"
      end

      attr_writer :stitch_directive

      # Names of stitching directives to omit from the composed supergraph.
      # @returns [Array<String>] list of stitching directive names.
      def stitching_directive_names
        [stitch_directive]
      end
    end
  end
end

require_relative "stitching/supergraph"
require_relative "stitching/client"
require_relative "stitching/composer"
require_relative "stitching/executor"
require_relative "stitching/http_executable"
require_relative "stitching/plan"
require_relative "stitching/planner"
require_relative "stitching/request"
require_relative "stitching/resolver"
require_relative "stitching/util"
require_relative "stitching/version"
