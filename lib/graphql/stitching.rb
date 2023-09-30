# frozen_string_literal: true

require "graphql"

module GraphQL
  module Stitching
    EMPTY_OBJECT = {}.freeze
    EMPTY_ARRAY = [].freeze

    class StitchingError < StandardError; end

    class << self
      def stitch_directive
        @stitch_directive ||= "stitch"
      end

      attr_writer :stitch_directive

      def stitching_directive_names
        [stitch_directive]
      end
    end
  end
end

require_relative "stitching/supergraph"
require_relative "stitching/boundary"
require_relative "stitching/client"
require_relative "stitching/composer"
require_relative "stitching/executor"
require_relative "stitching/http_executable"
require_relative "stitching/plan"
require_relative "stitching/planner_step"
require_relative "stitching/planner"
require_relative "stitching/request"
require_relative "stitching/selection_hint"
require_relative "stitching/shaper"
require_relative "stitching/skip_include"
require_relative "stitching/util"
require_relative "stitching/version"
