# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::SkipInclude" do
  def test_omits_statically_skipped_nodes
    render_skip_include "query {
      a {
        a
        b @skip(if: true)
        c @include(if: false)
      }
      b @skip(if: true)
      c @include(if: false)
    }"

    assert changed?
    assert_result "query {
      a { a }
    }"
  end

  def test_removes_conditional_directives_from_kept_nodes
    render_skip_include "query {
      a {
        a
        b @skip(if: false)
        c @include(if: true)
      }
      b @skip(if: false)
      c @include(if: true)
    }"

    assert changed?
    assert_result "query {
      a { a b c }
      b
      c
    }"
  end

  def test_omits_nodes_skipped_using_variables
    render_skip_include "query($skip: Boolean!, $include: Boolean!) {
      a {
        a
        b @skip(if: $skip)
        c @include(if: $include)
      }
      b @skip(if: $include)
      c @include(if: $skip)
    }", {
      "skip" => true,
      "include" => false,
    }

    assert changed?
    assert_result "query($skip: Boolean!, $include: Boolean!) {
      a { a }
      b
      c
    }"
  end

  def test_variables_may_reference_symbol_keys
    render_skip_include "query($skip: Boolean!, $include: Boolean!) {
      a {
        a
        b @skip(if: $skip)
        c @include(if: $include)
      }
    }", {
      skip: true,
      include: false,
    }

    assert changed?
    assert_result "query($skip: Boolean!, $include: Boolean!) {
      a { a }
    }"
  end

  def test_omitted_nodes_leaving_an_empty_scope_add_typename
    render_skip_include "query {
      a {
        b @skip(if: true)
        c @include(if: false)
      }
    }"

    assert changed?
    assert_result "query {
      a { _export___typename: __typename }
    }"
  end

  def test_lacking_conditionals_produces_no_changes
    render_skip_include "query {
      a { b c }
    }"

    assert !changed?
  end

  private

  def render_skip_include(source, variables = {})
    @source = source
    @changed = false
    @result = GraphQL::Stitching::SkipInclude.render(GraphQL.parse(@source), variables) do
      @changed = true
    end
  end

  def assert_result(result)
    assert_equal squish_string(result), squish_string(GraphQL::Language::Printer.new.print(@result))
  end

  def changed?
    @changed
  end
end
