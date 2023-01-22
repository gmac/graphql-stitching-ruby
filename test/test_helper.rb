# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'warning'
Gem.path.each do |path|
  # ignore warnings from auto-generated GraphQL lib code.
  Warning.ignore(/.*mismatched indentations.*/)
end

require 'bundler/setup'
Bundler.require(:default, :test)

require 'minitest/pride'
require 'minitest/autorun'
require 'graphql/stitching'
