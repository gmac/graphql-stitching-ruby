# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, merging visibility directives' do
  def setup
    skip unless GraphQL::Stitching.supports_visibility?
  end

  def test_merges_visibility_definitions
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String @visibility(profiles: ["a"]) }
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String @visibility(profiles: ["b"]) }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    visibility_def = supergraph.schema.directives[GraphQL::Stitching.visibility_directive]
    assert_equal ["a", "b"], visibility_def.get_argument("profiles").default_value
  end

  def test_collects_visibility_profiles_from_all_possible_locations
    schema_sdl = %|
      #{VISIBILITY_DEFINITION}

      interface TestInterface @visibility(profiles: ["interface"]) { 
        id: ID! @visibility(profiles: ["interface_field"])
      }

      type TestObject implements TestInterface @visibility(profiles: ["object"]) { 
        id: ID! @visibility(profiles: ["object_field"])
      }

      union TestUnion @visibility(profiles: ["union"]) = TestObject

      input TestInputObject @visibility(profiles: ["input_object"]) {
        id: ID! @visibility(profiles: ["input_object_arg"])
      }

      enum TestEnum @visibility(profiles: ["enum"]) {
        VALUE @visibility(profiles: ["enum_value"])
      }

      scalar TestScalar @visibility(profiles: ["scalar"])

      type Query { 
        test(
          input:TestInputObject @visibility(profiles: ["field_arg"]), 
          enum:TestEnum @visibility(profiles: ["field_arg"]), 
          scalar:TestScalar @visibility(profiles: ["field_arg"])
        ): TestInterface
      }
    |

    expected = [
      "enum",
      "enum_value",
      "extra",
      "field_arg",
      "input_object",
      "input_object_arg",
      "interface",
      "interface_field",
      "object",
      "object_field",
      "scalar",
      "union",
    ]

    supergraph = compose_definitions({ "a" => schema_sdl }, {
      visibility_profiles: ["extra"],
    })
    visibility_def = supergraph.schema.directives[GraphQL::Stitching.visibility_directive]
    assert_equal expected, visibility_def.get_argument("profiles").default_value
  end

  def test_intersects_visibility_profiles_across_locations
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String @visibility(profiles: ["a", "c", "d"]) }
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String @visibility(profiles: ["b", "c", "d"]) }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["c", "d"], get_profiles(supergraph.schema.get_type("Query").get_field("test"))
  end

  def test_locations_without_visibility_definition_do_not_constrain_others
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String @visibility(profiles: ["a", "b"]) }
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["a", "b"], get_profiles(supergraph.schema.get_type("Query").get_field("test"))
  end

  def test_no_intersecting_profiles_is_hidden
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String @visibility(profiles: ["a"]) }
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String @visibility(profiles: ["b"]) }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal [], get_profiles(supergraph.schema.get_type("Query").get_field("test"))
  end

  def test_intersecting_with_empty_profiles_is_hidden
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String @visibility(profiles: ["a"]) }
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:String @visibility(profiles: []) }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal [], get_profiles(supergraph.schema.get_type("Query").get_field("test"))
  end

  def test_merges_object_visibilities
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      type Test @visibility(profiles: ["a", "c"]) {
        test:String @visibility(profiles: ["a", "c"])
      }
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      type Test @visibility(profiles: ["b", "c"]) {
        test:String @visibility(profiles: ["b", "c"])
      }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test"))
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test").get_field("test"))
  end

  def test_merges_interface_visibilities
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      interface Test @visibility(profiles: ["a", "c"]) {
        test:String @visibility(profiles: ["a", "c"])
      }
      type Widget implements Test { test:String }
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      interface Test @visibility(profiles: ["b", "c"]) {
        test:String @visibility(profiles: ["b", "c"])
      }
      type Widget implements Test { test:String }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test"))
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test").get_field("test"))
  end

  def test_merges_enum_visibilities
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      enum Test @visibility(profiles: ["a", "c"]) {
        TEST @visibility(profiles: ["a", "c"])
      }
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      enum Test @visibility(profiles: ["b", "c"]) {
        TEST @visibility(profiles: ["b", "c"])
      }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test"))
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test").values["TEST"])
  end

  def test_merges_input_object_visibilities
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      input Test @visibility(profiles: ["a", "c"]) {
        test:String @visibility(profiles: ["a", "c"])
      }
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      input Test @visibility(profiles: ["b", "c"]) {
        test:String @visibility(profiles: ["b", "c"])
      }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test"))
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test").get_argument("test"))
  end

  def test_merges_scalar_visibilities
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      scalar Test @visibility(profiles: ["a", "c"])
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      scalar Test @visibility(profiles: ["b", "c"])
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test"))
  end

  def test_merges_union_visibilities
    a = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      type A { id:ID! }
      union Test @visibility(profiles: ["a", "c"]) = A
    |
    b = %|
      #{VISIBILITY_DEFINITION}
      type Query { test:Test }
      type B { id:ID! }
      union Test @visibility(profiles: ["b", "c"]) = B
    |

    supergraph = compose_definitions({ "a" => a, "b" => b })
    assert_equal ["c"], get_profiles(supergraph.schema.get_type("Test"))
  end

  private

  def get_profiles(element)
    element.directives.first.arguments.keyword_arguments[:profiles]
  end
end
