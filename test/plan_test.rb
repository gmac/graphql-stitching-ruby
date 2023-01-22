# frozen_string_literal: true

require "test_helper"
require_relative "schemas/basic_graph"

class GraphQL::Stitching::PlanTest < Minitest::Test
  def setup
    puts "hello"
  end

  def test_works
    assert_equal 1, 1
    byebug
  end
end

# describe 'Plan Test' do
#   before do
#     nil
#   end

#   it 'works' do
#     assert_equal 1, 1
#   end

#   it 'works' do
#     assert_equal 1, 0
#   end
# end
