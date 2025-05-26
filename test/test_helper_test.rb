# frozen_string_literal: true

require "test_helper"

describe "Test Helpers" do
  def test_squish_string
    string = %|
      {
        apple {
          ...on Apple { 
            id
            color
          }
        }
      }
    |
    assert_equal "{ apple { ...on Apple { id color } } }", squish_string(string)
  end

  def test_sorted_selection_matcher_formats_selections
    original = %|{
      banana
      ...on Coconut { 
        banana
        apple
      }
      coconut
      ... CoconutAttrs
      ...on Apple { 
        coconut 
        apple
        banana
      }
      apple
      ... BananaAttrs
    }|

    expected = %|query {
      apple
      banana
      coconut
      ... on Apple {
        apple
        banana
        coconut
      }
      ... on Coconut {
        apple
        banana
      }
      ...BananaAttrs
      ...CoconutAttrs
    }|

    matcher = SortedSelectionMatcher.new(original)
    assert_equal squish_string(expected), squish_string(matcher.source)
    assert matcher.match?(expected)
  end

  def test_sorted_selection_matcher_matches_fields
    matcher = SortedSelectionMatcher.new(%|{ banana apple }|)
    assert matcher.match?(%|{ apple banana }|)
    refute matcher.match?(%|{ apple coconut }|)
    refute matcher.match?(%|{ apple }|)
  end

  def test_sorted_selection_matcher_matches_inline_fragments
    matcher = SortedSelectionMatcher.new(%|{ ... on B { id } ...on A { id } }|)
    assert matcher.match?(%|{ ...on A { id } ...on B { id } }|)
    refute matcher.match?(%|{ ...on A { id } ...on B { key } }|)
    refute matcher.match?(%|{ ...on B { id } ...on C { id } }|)
  end

  def test_sorted_selection_matcher_matches_fragment_spreads
    matcher = SortedSelectionMatcher.new(%|{ ...B ...A }|)
    assert matcher.match?(%|{ ... A ... B }|)
    refute matcher.match?(%|{ ...A ...B ...C }|)
    refute matcher.match?(%|{ ...A ... C }|)
  end

  def test_use_static_version_is_false_by_default
    assert_equal false, GraphQL::Stitching::TypeResolver.use_static_version?
  end

  def test_use_static_version_is_true_in_helper_block
    begin
      with_static_resolver_version do
        assert_equal true, GraphQL::Stitching::TypeResolver.use_static_version?
        raise "block interrupt"
      end
    rescue
      assert_equal false, GraphQL::Stitching::TypeResolver.use_static_version?
    end
  end
end
