require "graphql"

module GraphQL
  module Stitching
    class << self

    end
  end
end

require_relative "stitching/composer"
require_relative "stitching/executor"
require_relative "stitching/operation"
require_relative "stitching/planner"
require_relative "stitching/remote_client"
require_relative "stitching/supergraph"
require_relative "stitching/util"
require_relative "stitching/version"
