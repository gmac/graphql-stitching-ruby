# frozen_string_literal: true

module GraphQL::Stitching
  class Composer
    class PermissionsMerger
      class << self
        def call(values_by_location, _info = nil)
          merged_scopes = values_by_location.values.reduce([]) do |acc, or_scopes|
            expanded_scopes = []
            or_scopes.each do |and_scopes|
              if acc.any?
                acc.each do |acc_scopes|
                  expanded_scopes << acc_scopes + and_scopes
                end
              else
                expanded_scopes << and_scopes.dup
              end
            end

            expanded_scopes
          end

          merged_scopes.each { _1.tap(&:uniq!).tap(&:sort!) }
          merged_scopes.tap(&:uniq!).tap(&:sort!)
        end
      end
    end
  end
end
