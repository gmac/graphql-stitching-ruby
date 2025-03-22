# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging object and interface fields' do

  def test_merges_field_descriptions
    a = %{type Test { """a""" field: String } type Query { test:Test }}
    b = %{type Test { """b""" field: String } type Query { test:Test }}

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      description_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.types["Test"].fields["field"].description
  end

  def test_merges_field_deprecations
    a = %{type Test { field: String @deprecated(reason:"a") } type Query { test:Test }}
    b = %{type Test { field: String @deprecated(reason:"b") } type Query { test:Test }}

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      deprecation_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.types["Test"].fields["field"].deprecation_reason
  end

  def test_merges_field_directives
    a = %|
      directive @fizzbuzz(arg: String!) on FIELD_DEFINITION
      type Query { test(arg:String):String @fizzbuzz(arg:"a") }
    |

    b = %|
      directive @fizzbuzz(arg: String!) on FIELD_DEFINITION
      type Query { test(arg:String):String @fizzbuzz(arg:"b") }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b }, {
      directive_kwarg_merger: ->(str_by_location, _info) { str_by_location.values.join("/") }
    })

    assert_equal "a/b", supergraph.schema.types["Query"].fields["test"].directives.first.arguments.keyword_arguments[:arg]
  end

  def test_merged_fields_use_common_nullability
    a = "type Test { field: String! } type Query { test:Test }"
    b = "type Test { field: String! } type Query { test:Test }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal "String!", supergraph.schema.types["Test"].fields["field"].type.to_type_signature
  end

  def test_merged_fields_use_weakest_nullability
    a = "type Test { field: String! } type Query { test:Test }"
    b = "type Test { field: String } type Query { test:Test }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal "String", supergraph.schema.types["Test"].fields["field"].type.to_type_signature
  end

  def test_merged_fields_must_have_matching_named_types
    a = "type Test { field: String } type Query { test:Test }"
    b = "type Test { field: Int } type Query { test:Test }"

    assert_error "Cannot compose mixed types at `Test.field`", CompositionError do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_fields_use_common_list_structure
    a = "type Test { field: [String!]! } type Query { test:Test }"
    b = "type Test { field: [String!]! } type Query { test:Test }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[String!]!", supergraph.schema.types["Test"].fields["field"].type.to_type_signature
  end

  def test_merged_fields_use_weakest_list_structure
    a = "type Test { field: [String!]! } type Query { test:Test }"
    b = "type Test { field: [String!] } type Query { test:Test }"
    c = "type Test { field: [String]! } type Query { test:Test }"

    supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c })
    assert_equal "[String]", supergraph.schema.types["Test"].fields["field"].type.to_type_signature
  end

  def test_merged_fields_allow_deep_list_structures
    a = "type Test { field: [[String!]!]! } type Query { test:Test }"
    b = "type Test { field: [[String]!] } type Query { test:Test }"

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal "[[String]!]", supergraph.schema.types["Test"].fields["field"].type.to_type_signature
  end

  def test_merged_fields_must_have_matching_list_structures
    a = "type Test { field: [[String!]] } type Query { test:Test }"
    b = "type Test { field: [String!] } type Query { test:Test }"

    assert_error "Cannot compose mixed list structures at `Test.field`", CompositionError do
      compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_merged_fields_permit_relay_connections
    a = %|
      type AppleConnection { edges: [AppleEdge!]! nodes: [Apple!]! } 
      type AppleEdge { cursor: String! node: Apple! } 
      type Apple { id: ID! } 
      type Query { apple(first: Int, last: Int, before: String, after: String): AppleConnection }
    |
    b = %|
      type BananaConnection { edges: [BananaEdge!]! nodes: [Banana!]! } 
      type BananaEdge { cursor: String! node: Banana! } 
      type Banana { id: ID! } 
      type Query { banana(first: Int, last: Int, before: String, after: String): BananaConnection }
    |

    assert compose_definitions({ "a" => a, "b" => b })
  end

  def test_creates_delegation_map
    a = %{type Test { id: ID!, a: String c: String } type Query { a(id: ID!):Test @stitch(key: "id") }}
    b = %{type Test { id: ID!, b: String c: String } type Query { b(id: ID!):Test @stitch(key: "id") }}
    supergraph = compose_definitions({ "a" => a, "b" => b })

    expected_fields_map = {
      "Test" => {
        "id" => ["a", "b"],
        "a" => ["a"],
        "b" => ["b"],
        "c" => ["a", "b"],
      },
      "Query" => {
        "a" => ["a"],
        "b" => ["b"]
      },
    }

    assert_equal expected_fields_map, supergraph.fields
  end
end
