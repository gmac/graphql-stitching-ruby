# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, configuration' do

  def test_perform_with_executable_config
    executable = Proc.new { true }
    supergraph = GraphQL::Stitching::Composer.new.perform({
      storefronts: {
        schema: GraphQL::Schema.from_definition("type Query { ping: String! }"),
        executable: executable,
      }
    })

    assert_equal executable, supergraph.executables["storefronts"]
  end

  def test_perform_with_static_boundary_config
    alpha = %|
      type Product { id: ID! name: String! }
      type Query { productA(id: ID!): Product }
    |

    bravo = %|
      type Product { id: ID! price: Float! }
      type Query { productB(key: ID, other: String): Product }
    |

    supergraph = GraphQL::Stitching::Composer.new.perform({
      alpha: {
        schema: GraphQL::Schema.from_definition(alpha),
        stitch: [
          { field_name: "productA", key: "id" },
        ]
      },
      bravo: {
        schema: GraphQL::Schema.from_definition(bravo),
        stitch: [
          { field_name: "productB", key: "key:id" },
        ]
      }
    })

    expected_boundaries = {
      "Product" => [
        GraphQL::Stitching::Boundary.new(
          location: "alpha",
          type_name: "Product",
          field: "productA",
          key: "id",
          arg: "id",
          list: false,
        ),
        GraphQL::Stitching::Boundary.new(
          location: "bravo",
          type_name: "Product",
          field: "productB",
          key: "id",
          arg: "key",
          list: false,
        ),
      ]
    }

    assert_equal expected_boundaries, supergraph.boundaries
  end
end
