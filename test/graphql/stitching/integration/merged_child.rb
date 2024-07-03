# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/merged_child"

describe 'GraphQL::Stitching, merged child' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::MergedChild::ParentSchema,
      "b" => Schemas::MergedChild::ChildSchema,
    })

    @expected = {
      "author" => {
        "name" => "Frank Herbert",
        "book" => {
          "title" => "Dune",
          "year" => 1965,
        },
      },
    }
  end

  def test_resolves_fragment_spread_for_parent_of_merged_child
    result = plan_and_execute(@supergraph, %|
      query {
        author { ...AuthorAttrs }
      }
      fragment AuthorAttrs on Author {
        name
        book {
          title
          year
        }
      }
    |)

    assert_equal @expected, result["data"]
  end

  def test_resolves_inline_fragment_for_parent_of_merged_child
    result = plan_and_execute(@supergraph, %|
      query {
        author {
          ...on Author {
            name
            book {
              title
              year
            }
          }
        }
      }
    |)

    assert_equal @expected, result["data"]
  end

  def test_resolves_untyped_fragment_for_parent_of_merged_child
    result = plan_and_execute(@supergraph, %|
      query {
        author {
          ... {
            name
            book {
              title
              year
            }
          }
        }
      }
    |)

    assert_equal @expected, result["data"]
  end
end
