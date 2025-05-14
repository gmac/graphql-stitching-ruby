# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, authorization' do
  class AuthTester
    extend GraphQL::Stitching::Composer::Authorization
    def self.merge(*scopes)
      merge_authorization_scopes(*scopes)
    end
  end

  def test_merges_multiple_unique_permission_scopes
    result = {
      "alpha" => [["a", "b"], ["c"]],
      "bravo" => [["x", "y"], ["z"]],
      "delta" => [["q"]],
    }.each_value.reduce([]) do |base, scopes|
      AuthTester.merge(base, scopes)
    end

    expected = [
      ["a", "b", "q", "x", "y"],
      ["a", "b", "q", "z"],
      ["c", "q", "x", "y"],
      ["c", "q", "z"],
    ]

    assert_equal expected, result
  end

  def test_merges_multiple_permission_scopes_with_duplicates
    result = {
      "alpha" => [["a", "b"], ["x"]],
      "bravo" => [["a", "c"], ["y"]],
    }.each_value.reduce([]) do |base, scopes|
      AuthTester.merge(base, scopes)
    end

    expected = [
      ["a", "b", "c"],
      ["a", "b", "y"],
      ["a", "c", "x"],
      ["x", "y"],
    ]

    assert_equal expected, result
  end

  def test_merges_and_deduplicates_multiple_or_scopes
    result = {
      "alpha" => [["a", "b", "c"]],
      "bravo" => [["a"], ["b"], ["c"]],
    }.each_value.reduce([]) do |base, scopes|
      AuthTester.merge(base, scopes)
    end

    expected = [
      ["a", "b", "c"],
    ]

    assert_equal expected, result
  end

  def test_identical_merges_are_idempotent
    result = {
      "alpha" => [["a", "b"], ["c"]],
      "bravo" => [["a", "b"], ["c"]],
    }.each_value.reduce([]) do |base, scopes|
      AuthTester.merge(base, scopes)
    end

    result = {
      "alpha" => result,
      "bravo" => [["a", "b"], ["c"]],
    }.each_value.reduce([]) do |base, scopes|
      AuthTester.merge(base, scopes)
    end

    expected = [
      ["a", "b"], ["a", "b", "c"], ["c"],
    ]

    assert_equal expected, result
  end

  def test_merges_field_authorizations
    a = %|
      #{AUTHORIZATION_DEFINITION}
      type Query { 
        test: String @authorization(scopes: [["a"]])
      }
    |

    b = %|
      #{AUTHORIZATION_DEFINITION}
      type Query { 
        test: String @authorization(scopes: [["b"]])
      }
    |

    sg = compose_definitions({ "a" => a, "b" => b })
    assert_equal [["a", "b"]], get_scopes(sg.schema.query.get_field("test"))
  end

  def test_merges_leaf_authorizations
    a = %|
      #{AUTHORIZATION_DEFINITION}
      scalar URL @authorization(scopes: [["a"]])
      enum Enum @authorization(scopes: [["a"]]) { YES }
      type Query { 
        url: URL
        enum: Enum
      }
    |

    b = %|
      #{AUTHORIZATION_DEFINITION}
      scalar URL @authorization(scopes: [["b"]])
      enum Enum @authorization(scopes: [["b"]]) { YES }
      type Query { 
        url: URL
        enum: Enum
      }
    |

    sg = compose_definitions({ "a" => a, "b" => b })
    assert_equal [["a", "b"]], get_scopes(sg.schema.query.get_field("url"))
    assert_equal [["a", "b"]], get_scopes(sg.schema.query.get_field("enum"))
  end

  def test_merges_object_and_field_authorizations
    a = %|
      #{STITCH_DEFINITION}
      #{AUTHORIZATION_DEFINITION}
      type T @authorization(scopes: [["a"]]) {
        id: ID!
        x: String
      }
      type Query { 
        t(id: ID!): T @stitch(key: "id")
      }
    |

    b = %|
      #{STITCH_DEFINITION}
      #{AUTHORIZATION_DEFINITION}
      type T {
        id: ID! @authorization(scopes: [["b"]])
      }
      type Query { 
        t(id: ID!): T @stitch(key: "id")
      }
    |

    sg = compose_definitions({ "a" => a, "b" => b })
    assert_equal [["a", "b"]], get_scopes(sg.schema.get_type("T").get_field("id"))
    assert_equal [["a"]], get_scopes(sg.schema.get_type("T").get_field("x"))
    assert_nil get_scopes(sg.schema.query.get_field("t"))
  end

  private

  def get_scopes(element)
    authorization = element.directives.find { _1.graphql_name == GraphQL::Stitching.authorization_directive }
    return if authorization.nil?

    authorization.arguments.keyword_arguments[:scopes]
  end
end
