# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Supergraph visibility controls" do
  def setup
    skip unless GraphQL::Stitching.supports_visibility?
    
    @exec = { alpha: Proc.new { true } }
  end

  def test_activates_visibility_profile_definitions_and_nil_profile
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      type Query { 
        a: String
        b: String @visibility(profiles: ["private"])
        c: String @visibility(profiles: [])
      }
    |

    supergraph = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    profiles = supergraph.schema.visibility.instance_variable_get(:@profiles).keys.map(&:to_s)
    assert_equal ["", "private", "public"], profiles.sort
  end

  def test_to_definition_prints_specific_profile
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      type Query { 
        a: String
        b: String @visibility(profiles: ["private"])
        c: String @visibility(profiles: [])
      }
    |

    expected_public = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      type Query { 
        a: String
      }
    |

    expected_private = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      type Query { 
        a: String
        b: String @visibility(profiles: ["private"])
      }
    |

    supergraph = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    assert_equal squish_string(schema_sdl), squish_string(supergraph.to_definition)
    assert_equal squish_string(expected_public), squish_string(supergraph.to_definition(visibility_profile: "public"))
    assert_equal squish_string(expected_private), squish_string(supergraph.to_definition(visibility_profile: "private"))
  end

  def test_controls_field_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      type Query { 
        a: Boolean
        b: Boolean @visibility(profiles: ["private"])
        c: Boolean @visibility(profiles: [])
      }
    |

    query = %|{ a b c }|
    
    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "b" },
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  def test_controls_field_argument_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      type Query { 
        test(
          a: String,
          b: String @visibility(profiles: ["private"]),
          c: String @visibility(profiles: []),
        ): Boolean
      }
    |

    query = %|{ test(a: "", b: "", c: "") }|

    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "argumentNotAccepted", "name"=>"test", "typeName" => "Field", "argumentName" => "b" },
      { "code" => "argumentNotAccepted", "name"=>"test", "typeName" => "Field", "argumentName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  def test_controls_object_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      type A { id: ID! }
      type B @visibility(profiles: ["private"]) { id: ID! }
      type C @visibility(profiles: []) { id: ID! }
      type Query { 
        a: A
        b: B
        c: C
      }
    |

    query = %|{
      a { id }
      b { id }
      c { id }
    }|
    
    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "b" },
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  def test_controls_interface_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      interface A { id: ID! }
      interface B @visibility(profiles: ["private"]) { id: ID! }
      interface C @visibility(profiles: []) { id: ID! }
      type T implements A & B & C { id: ID! }
      type Query { 
        a: A
        b: B
        c: C
      }
    |

    query = %|{
      a { id }
      b { id }
      c { id }
    }|
    
    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "b" },
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  def test_controls_enum_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      enum A { YES }
      enum B @visibility(profiles: ["private"]) { MAYBE }
      enum C @visibility(profiles: []) { NO }
      type Query { 
        a: A
        b: B
        c: C
      }
    |

    query = %|{ a b c }|
    
    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "b" },
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  def test_controls_enum_value_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      enum Test {
        YES
        NO @visibility(profiles: ["private"])
        MAYBE @visibility(profiles: [])
      }
      type Query { 
        test(a: Test!, b: Test!, c: Test!): Boolean
      }
    |

    query = %|{ test(a: YES, b: NO, c: MAYBE) }|

    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "argumentLiteralsIncompatible", "typeName" => "Field", "argumentName" => "b" },
      { "code" => "argumentLiteralsIncompatible", "typeName" => "Field", "argumentName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  def test_controls_input_object_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      input A { id: Int }
      input B @visibility(profiles: ["private"]) { id: Int }
      input C @visibility(profiles: []) { id: Int }
      type Query { 
        test(a: A, b: B, c: C): Boolean
      }
    |

    query = %|{ test(a: { id:1 }, b: { id:2 }, c: { id:3 }) }|
    
    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "argumentNotAccepted", "name" => "test", "typeName" => "Field", "argumentName" => "b" },
      { "code" => "argumentNotAccepted", "name" => "test", "typeName" => "Field", "argumentName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  def test_controls_input_object_argument_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      input Test {
        a: String
        b: String @visibility(profiles: ["private"])
        c: String @visibility(profiles: [])
      }
      type Query { 
        test(input: Test!): Boolean
      }
    |

    query = %|{ test(input: { a: "", b: "", c: "" }) }|

    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "argumentNotAccepted", "name"=>"Test", "typeName" => "InputObject", "argumentName" => "b" },
      { "code" => "argumentNotAccepted", "name"=>"Test", "typeName" => "InputObject", "argumentName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  def test_controls_scalar_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      scalar A
      scalar B @visibility(profiles: ["private"])
      scalar C @visibility(profiles: [])
      type Query { 
        a: A
        b: B
        c: C
      }
    |

    query = %|{ a b c }|
    
    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "b" },
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  def test_controls_union_visibility
    schema_sdl = %|
      #{visibility_definition_with_profiles(["public", "private"])}
      type T { id: ID! }
      union A = T
      union B @visibility(profiles: ["private"]) = T
      union C @visibility(profiles: []) = T
      type Query { 
        a: A
        b: B
        c: C
      }
    |

    query = %|{ 
      a { ...on T { id } }
      b { ...on T { id } }
      c { ...on T { id } }
    }|
    
    sg = GraphQL::Stitching::Supergraph.from_definition(schema_sdl, executables: @exec)
    errors_nil = GraphQL::Stitching::Request.new(sg, query, context: {}).validate
    errors_pub = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "public" }).validate
    errors_pri = GraphQL::Stitching::Request.new(sg, query, context: { visibility_profile: "private" }).validate
    
    expected_pub = [
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "b" },
      { "code" => "undefinedField", "typeName" => "Query", "fieldName" => "c" },
    ]

    assert errors_nil.empty?
    assert_error_extensions expected_pub, errors_pub
    assert_error_extensions [expected_pub.last], errors_pri
  end

  private

  def visibility_definition_with_profiles(profiles)
    VISIBILITY_DEFINITION.sub(
      %|@visibility(profiles: [String!]!)|, 
      %|@visibility(profiles: [String!]! = #{profiles.to_json.gsub!(%|","|, %|", "|)})|,
    )
  end

  def assert_error_extensions(expected, errors)
    assert_equal expected, errors.map(&:to_h).map! { _1["extensions"] }
  end
end
