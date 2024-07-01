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

  def test_perform_with_static_resolver_config
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
          { field_name: "productB", key: "id", arguments: "key: $.id" },
        ]
      }
    })

    expected_resolvers = {
      "Product" => [
        GraphQL::Stitching::Resolver.new(
          location: "alpha",
          type_name: "Product",
          list: false,
          field: "productA",
          key: GraphQL::Stitching::Resolver.parse_key("id"),
          arguments: GraphQL::Stitching::Resolver.parse_arguments_with_type_defs("id: $.id", "id: ID"),
        ),
        GraphQL::Stitching::Resolver.new(
          location: "bravo",
          type_name: "Product",
          list: false,
          field: "productB",
          key: GraphQL::Stitching::Resolver.parse_key("id"),
          arguments: GraphQL::Stitching::Resolver.parse_arguments_with_type_defs("key: $.id", "key: ID"),
        ),
      ]
    }

    assert_equal expected_resolvers, supergraph.resolvers
  end

  def test_perform_federation_schema
    schema = %|
      directive @key(fields: String!) repeatable on OBJECT
      type Product @key(fields: "id sku") { id: ID! sku: String! price: Float! }
      union _Entity = Product
      scalar _Any
      type Query { _entities(representations: [_Any!]!): [_Entity]! }
    |

    configs = GraphQL::Stitching::Composer::ResolverConfig.extract_federation_entities(
      GraphQL::Schema.from_definition(schema),
      "alpha",
    )

    resolver_config = configs["alpha._entities"].first
    assert_equal "Product", resolver_config.type_name
    assert_equal "id sku", resolver_config.key
    assert_equal "representations: { id: $.id, sku: $.sku, __typename: $.__typename }", resolver_config.arguments
  end
end
