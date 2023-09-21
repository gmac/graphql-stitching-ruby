# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::SkipInclude" do
  QUERY = "query First {
    alpha @include(if: false)
    bravo @skip(if: false) {
      charlie @skip(if: true)
    }
  }
  fragment Boo on Sfoo {
    soo
  }"

  def test_builds_with_pre_parsed_ast
    document = GraphQL.parse(QUERY)
    result, changed = GraphQL::Stitching::SkipInclude.render(document, {})
    puts GraphQL::Language::Printer.new.print(result)
  end
end
