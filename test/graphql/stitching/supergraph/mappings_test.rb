# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"

describe "GraphQL::Stitching::Supergraph mappings" do
  class ComposedSchema < GraphQL::Schema
    class Product < GraphQL::Schema::Object
      # products, storefronts
      field :upc, ID, null: false
      # products
      field :name, String, null: false
      # products
      field :price, Int, null: false
      # products
      field :manufacturer, "ComposedSchema::Manufacturer", null: false
    end

    class Manufacturer < GraphQL::Schema::Object
      # products, manufacturers
      field :id, ID, null: false
      # manufacturers
      field :name, String, null: false
      # manufacturers
      field :address, String, null: false
      # products
      field :products, [Product], null: false
    end

    class Storefront < GraphQL::Schema::Object
      # storefronts
      field :id, ID, null: false
      # storefronts
      field :name, String, null: false
      # storefronts
      field :products, [Product], null: false
    end

    class Query < GraphQL::Schema::Object
      # manufacturers
      field :manufacturer, Manufacturer, null: true do
        argument :id, ID, required: true
      end

      # products
      field :product, Product, null: true do
        argument :upc, ID, required: true
      end

      # storefronts
      field :storefront, Storefront, null: true do
        argument :id, ID, required: true
      end
    end

    query Query
  end

  FIELDS_MAP = {
    "Manufacturer" => {
      "id" => ["manufacturers", "products"],
      "name" => ["manufacturers"],
      "address" => ["manufacturers"],
      "products" => ["products"],
    },
    "Product" => {
      "upc" => ["products", "storefronts"],
      "name" => ["products"],
      "price" => ["products"],
      "manufacturer" => ["products"],
    },
    "Storefront" => {
      "id" => ["storefronts"],
      "name" => ["storefronts"],
      "products" => ["storefronts"],
    },
    "Query" => {
      "manufacturer" => ["manufacturers"],
      "product" => ["products"],
      "storefront" => ["storefronts"],
    },
  }

  RESOLVERS_MAP = {
    "Manufacturer" => [
      GraphQL::Stitching::TypeResolver.new(
        location: "manufacturers",
        field: "manufacturer",
        key: GraphQL::Stitching::TypeResolver.parse_key("id", FIELDS_MAP.dig("Manufacturer", "id")),
        arguments: GraphQL::Stitching::TypeResolver.parse_arguments_with_type_defs("id: $.id", "id: ID"),
      ),
    ],
    "Product" => [
      GraphQL::Stitching::TypeResolver.new(
        location: "products",
        field: "products",
        key: GraphQL::Stitching::TypeResolver.parse_key("upc", FIELDS_MAP.dig("Product", "upc")),
        arguments: GraphQL::Stitching::TypeResolver.parse_arguments_with_type_defs("upc: $.upc", "upc: ID"),
      ),
    ],
    "Storefront" => [
      GraphQL::Stitching::TypeResolver.new(
        location: "storefronts",
        field: "storefronts",
        key: GraphQL::Stitching::TypeResolver.parse_key("id", FIELDS_MAP.dig("Storefront", "id")),
        arguments: GraphQL::Stitching::TypeResolver.parse_arguments_with_type_defs("id: $.id", "id: ID"),
      ),
    ],
  }

  def test_fields_by_type_and_location
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Class.new(ComposedSchema),
      fields: FIELDS_MAP.dup,
      resolvers: RESOLVERS_MAP,
    )

    mapping = supergraph.fields_by_type_and_location
    assert_equal FIELDS_MAP.keys.sort, mapping.keys.sort - supergraph.memoized_introspection_types.keys
    assert_equal ["address", "id", "name"], mapping["Manufacturer"]["manufacturers"].sort
    assert_equal ["id", "products"], mapping["Manufacturer"]["products"].sort
  end

  def test_locations_by_type
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Class.new(ComposedSchema),
      fields: FIELDS_MAP.dup,
      resolvers: RESOLVERS_MAP,
    )

    mapping = supergraph.locations_by_type
    assert_equal FIELDS_MAP.keys.sort, mapping.keys.sort - supergraph.memoized_introspection_types.keys
    assert_equal ["manufacturers", "products"], mapping["Manufacturer"].sort
    assert_equal ["products", "storefronts"], mapping["Product"].sort
  end

  def test_possible_keys_for_type_and_location
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Class.new(ComposedSchema),
      fields: FIELDS_MAP.dup,
      resolvers: RESOLVERS_MAP,
    )

    assert_equal ["upc"], supergraph.possible_keys_for_type_and_location("Product", "products").map(&:to_definition)
    assert_equal ["upc"], supergraph.possible_keys_for_type_and_location("Product", "storefronts").map(&:to_definition)
    assert_equal [], supergraph.possible_keys_for_type_and_location("Product", "manufacturers")
  end

  def test_adds_supergraph_location_for_expected_introspection_types
    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Class.new(ComposedSchema),
      fields: FIELDS_MAP.dup,
      resolvers: RESOLVERS_MAP,
    )

    ["__Schema", "__Type", "__Field"].each do |introspection_type|
      assert supergraph.locations_by_type_and_field[introspection_type], "Missing introspection type"
      assert_equal ["__super"], supergraph.locations_by_type_and_field[introspection_type].values.first
    end
  end

  def test_assign_valid_executables_with_string_locations
    executable1 = Schemas::Example::Products
    executable2 = GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3000")
    executable3 = Proc.new { true }

    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Class.new(ComposedSchema),
      fields: FIELDS_MAP.dup,
      resolvers: RESOLVERS_MAP,
      executables: {
        "products" => executable1,
        "storefronts" => executable2,
        "manufacturers" => executable3,
      },
    )

    assert_equal ["__super", "manufacturers", "products", "storefronts"], supergraph.executables.keys.sort
    assert_equal executable1, supergraph.executables["products"]
    assert_equal executable2, supergraph.executables["storefronts"]
    assert_equal executable3, supergraph.executables["manufacturers"]
  end

  def test_assign_valid_executables_with_symbol_locations
    executable1 = Schemas::Example::Products
    executable2 = GraphQL::Stitching::HttpExecutable.new(url: "http://localhost:3000")
    executable3 = Proc.new { true }

    supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Class.new(ComposedSchema),
      fields: FIELDS_MAP.dup,
      resolvers: RESOLVERS_MAP,
      executables: {
        products: executable1,
        storefronts: executable2,
        manufacturers: executable3,
      },
    )

    assert_equal ["__super", "manufacturers", "products", "storefronts"], supergraph.executables.keys.sort
    assert_equal executable1, supergraph.executables["products"]
    assert_equal executable2, supergraph.executables["storefronts"]
    assert_equal executable3, supergraph.executables["manufacturers"]
  end

  def test_rejects_invalid_executables_with_error
    assert_error "Invalid executable provided for location" do
      GraphQL::Stitching::Supergraph.new(
        schema: Class.new(ComposedSchema),
        fields: FIELDS_MAP.dup,
        resolvers: RESOLVERS_MAP,
        executables: {
          products: "nope",
        },
      )
    end
  end

  def test_route_type_to_locations_connects_types_across_locations
    a = %|
      type T { upc:ID! }
      type Query { a(upc:ID!):T @stitch(key: "upc") }
    |
    b = %|
      type T { id:ID! upc:ID! }
      type Query {
        ba(upc:ID!):T @stitch(key: "upc")
        bc(id:ID!):T @stitch(key: "id")
      }
    |
    c = %|
      type T { id:ID! }
      type Query { c(id:ID!):T @stitch(key: "id") }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c })

    routes = supergraph.route_type_to_locations("T", "a", ["b", "c"])
    assert_equal ["b"], routes["b"].map { _1.location }
    assert_equal ["b", "c"], routes["c"].map { _1.location }

    routes = supergraph.route_type_to_locations("T", "b", ["a", "c"])
    assert_equal ["a"], routes["a"].map { _1.location }
    assert_equal ["c"], routes["c"].map { _1.location }

    routes = supergraph.route_type_to_locations("T", "c", ["a", "b"])
    assert_equal ["b", "a"], routes["a"].map { _1.location }
    assert_equal ["b"], routes["b"].map { _1.location }
  end

  def test_route_type_to_locations_favors_longer_paths_through_necessary_locations
    a = %|
      type T { id:ID! }
      type Query { a(id:ID!):T @stitch(key: "id") }
    |
    b = %|
      type T { id:ID! upc:ID! }
      type Query {
        ba(id:ID!):T @stitch(key: "id")
        bc(upc:ID!):T @stitch(key: "upc")
      }
    |
    c = %|
      type T { upc:ID! gid:ID! }
      type Query {
        cb(upc:ID!):T @stitch(key: "upc")
        cd(gid:ID!):T @stitch(key: "gid")
      }
    |
    d = %|
      type T { gid:ID! code:ID! }
      type Query {
        dc(gid:ID!):T @stitch(key: "gid")
        de(code:ID!):T @stitch(key: "code")
      }
    |
    e = %|
      type T { code:ID! id:ID! }
      type Query {
        ed(code:ID!):T @stitch(key: "code")
        ea(id:ID!):T @stitch(key: "id")
      }
    |

    supergraph = compose_definitions({ "a" => a, "b" => b, "c" => c, "d" => d, "e" => e })

    routes = supergraph.route_type_to_locations("T", "a", ["b", "c", "d"])
    assert_equal ["b", "c", "d"], routes["d"].map { _1.location }
    assert routes.none? { |_key, path| path.any? { _1.location == "e" } }
  end
end
