require "graphql"

module GraphQL
  module Stitching
    class << self

    end
  end
end

require_relative "stitching/boundary"
require_relative "stitching/composer"
require_relative "stitching/execute"
require_relative "stitching/graph_context"
require_relative "stitching/operation"
require_relative "stitching/planner"
require_relative "stitching/util"
require_relative "stitching/version"
