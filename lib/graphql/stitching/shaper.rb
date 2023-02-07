# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Shaper
      def self.perform(schema, document, raw_result)
        # - Traverse the document (same basic steps as Planner.extract_locale_selections)
        # - Recursively reduce result nodes based on schema rules...
        # - For each scope:
        #   - Eliminate extra attributes (stitching artifacts)
        #   - Add missing fields requested in the document, value is null
        # - Not-null violations invalidate the scope, and invalidations bubble

        raw_result
      end
    end
  end
end
