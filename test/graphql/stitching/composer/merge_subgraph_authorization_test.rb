# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, SubgraphAuthorization' do
  SubgraphAuthorization = GraphQL::Stitching::Composer::SubgraphAuthorization

  def test_applies_scalar_scopes_to_returning_fields
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      scalar T @authorization(scopes: [["s"]])
      type Query {
        a: String
        t: T
      }
    |)

    expected = { 
      "Query" => { 
        "t" => [["s"]],
      },
    }
    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_applies_enum_scopes_to_returning_fields
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      enum T @authorization(scopes: [["s"]]) { YES }
      type Query {
        a: String
        t: T
      }
    |)

    expected = { 
      "Query" => { 
        "t" => [["s"]],
      },
    }
    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_applies_object_scopes_to_child_and_returning_fields
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      type T @authorization(scopes: [["s"]]) {
        a: String
        b: String
      }
      type Query {
        a: String
        t: T
      }
    |)

    expected = { 
      "T" => { 
        "a" => [["s"]],
        "b" => [["s"]],
      },
    }
    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_applies_interface_scopes_to_child_implementing_and_returning_fields
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      interface I @authorization(scopes: [["s"]]) {
        a: String
        b: String
      }
      type T implements I {
        a: String
        b: String
        c: String
      }
      type Query {
        i: I
        t: T
      }
    |)

    expected = {
      "I" => { 
        "a" => [["s"]],
        "b" => [["s"]],
      },
      "T" => {
        "a" => [["s"]],
        "b" => [["s"]],
      },
    }
    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_applies_object_field_scopes
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      type Query {
        a: String @authorization(scopes: [["s"]])
        b: String
      }
    |)

    expected = { 
      "Query" => { 
        "a" => [["s"]],
      },
    }
    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_applies_interface_field_scopes
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      interface I {
        a: String @authorization(scopes: [["s"]])
        b: String
      }
      type T implements I {
        a: String
        b: String
      }
      type Query {
        i: I
        t: T
      }
    |)

    expected = { 
      "I" => { 
        "a" => [["s"]],
      },
      "T" => { 
        "a" => [["s"]],
      },
    }
    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_merges_object_and_field_scopes
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      type T @authorization(scopes: [["s1"]]) {
        a: String @authorization(scopes: [["s2"]])
        b: String
      }
      type Query {
        t: T @authorization(scopes: [["s3"]])
      }
    |)

    expected = { 
      "T" => { 
        "a" => [["s1", "s2"]],
        "b" => [["s1"]],
      },
      "Query" => { 
        "t" => [["s3"]],
      },
    }
    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_merges_interface_object_leaf_and_field_scopes
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      scalar Widget @authorization(scopes: [["s0"]])
      interface I @authorization(scopes: [["s1"]]) {
        a: Widget @authorization(scopes: [["s2"]])
        b: String
      }
      type T implements I @authorization(scopes: [["s3"]]) {
        a: Widget @authorization(scopes: [["s4"]])
        b: String
        c: String
      }
      type Query {
        i: I @authorization(scopes: [["s5"]])
        t: T @authorization(scopes: [["s6"]])
      }
    |)

    expected = {
      "I" => { 
        "a" => [["s0", "s1", "s2"]],
        "b" => [["s1"]],
      },
      "T" => { 
        "a" => [["s0", "s1", "s2", "s3", "s4"]],
        "b" => [["s1", "s3"]],
        "c" => [["s3"]],
      },
      "Query" => { 
        "i" => [["s5"]],
        "t" => [["s6"]],
      },
    }
    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_merges_inherited_interfaces
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      interface IX @authorization(scopes: [["s1"]]) {
        a: String @authorization(scopes: [["s2"]])
      }
      interface IY implements IX {
        a: String
        b: String
      }
      type T implements IY {
        a: String
        b: String
        c: String
      }
      type Query {
        ix: IX
        iy: IY
        t: T
      }
    |)

    expected = {
      "IX" => { 
        "a" => [["s1", "s2"]],
      },
      "IY" => { 
        "a" => [["s1", "s2"]],
      },
      "T" => { 
        "a" => [["s1", "s2"]],
      },
    }
    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_merges_or_scopes_via_matrix_multiplication
    schema = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      type Query @authorization(scopes: [["read:query"], ["read:root"]]) {
        e: Enum! @authorization(scopes: [
          ["read:private", "read:field"],
          ["read:private", "read:object"]
        ])
      }
      enum Enum @authorization(scopes: [["read:enum"]]) {
        VALUE
      }
    |)

    expected = {
      "Query" => { 
        "e" => [
          ["read:enum", "read:field", "read:private", "read:query"],
          ["read:enum", "read:field", "read:private", "read:root"],
          ["read:enum", "read:object", "read:private", "read:query"],
          ["read:enum", "read:object", "read:private", "read:root"],  
        ],
      },
    }

    assert_equal expected, SubgraphAuthorization.new(schema).collect
  end

  def test_merge_authorizations_across_subgraph_compositions
    schema1 = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      type T @authorization(scopes: [["s1"]]) {
        a: String
      }
      type Query {
        t: T @authorization(scopes: [["s2"]])
      }
    |)

    schema2 = GraphQL::Schema.from_definition(%|
      #{AUTHORIZATION_DEFINITION}
      type T {
        a: String @authorization(scopes: [["s3"]])
      }
      type Query @authorization(scopes: [["s4"]]) {
        t: T
      }
    |)

    expected = {
      "T" => {
        "a" => [["s1", "s3"]],
      },
      "Query" => { 
        "t" => [["s2", "s4"]],
      },
    }

    acc = [schema1, schema2].each_with_object({}) do |schema, memo|
      SubgraphAuthorization.new(schema).reverse_merge!(memo)
    end
    assert_equal expected, acc
  end
end
