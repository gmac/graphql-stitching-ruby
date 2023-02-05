# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, boundaries" do
  def build_sample_graph
    @storefronts_sdl = "
      type Storefront {
        id: ID!
        name: String!
        products: [Product]!
      }
      type Product {
        upc: ID!
      }
      type Query {
        storefront(id: ID!): Storefront
      }
    "

    @products_sdl = "
      type Product {
        upc: ID!
        name: String!
        price: Float!
        manufacturer: Manufacturer!
      }
      type Manufacturer {
        id: ID!
        name: String!
        products: [Product]!
      }
      type Query {
        product(upc: ID!): Product @boundary(key: \"upc\")
        productsManufacturer(id: ID!): Manufacturer @boundary(key: \"id\")
      }
    "

    @manufacturers_sdl = "
      type Manufacturer {
        id: ID!
        name: String!
        address: String!
      }
      type Query {
        manufacturer(id: ID!): Manufacturer @boundary(key: \"id\")
      }
    "

    compose_definitions({
      "storefronts" => @storefronts_sdl,
      "products" => @products_sdl,
      "manufacturers" => @manufacturers_sdl,
    })
  end

  def test_collects_unique_fields_across_boundary_locations
    document = "
      query {
        storefront(id: \"1\") {
          name
          products {
            name
            manufacturer {
              address
              products {
                name
              }
            }
          }
        }
      }
    "

    plan = GraphQL::Stitching::Planner.new(
      supergraph: build_sample_graph,
      document: GraphQL::Stitching::Document.new(document),
    ).perform

    assert_equal 3, plan.operations.length

    first = plan.operations[0]
    assert_equal "storefronts", first.location
    assert_equal "query", first.operation_type
    assert_equal [], first.insertion_path
    assert_equal "{ storefront(id: \"1\") { name products { _STITCH_upc: upc } } }", first.selection_set
    assert_nil first.boundary
    assert_nil first.after_key

    second = plan.operations[1]
    assert_equal "products", second.location
    assert_equal "query", second.operation_type
    assert_equal ["storefront", "products"], second.insertion_path
    assert_equal "{ name manufacturer { products { name } _STITCH_id: id } }", second.selection_set
    assert_equal "product", second.boundary["field"]
    assert_equal "upc", second.boundary["selection"]
    assert_equal first.key, second.after_key

    third = plan.operations[2]
    assert_equal "manufacturers", third.location
    assert_equal "query", third.operation_type
    assert_equal ["storefront", "products", "manufacturer"], third.insertion_path
    assert_equal "{ address }", third.selection_set
    assert_equal "manufacturer", third.boundary["field"]
    assert_equal "id", third.boundary["selection"]
    assert_equal second.key, third.after_key
  end

  def test_collects_common_fields_from_first_available_location
    supergraph = build_sample_graph
    document1 = "{         manufacturer(id: \"1\") { name products { name } } }"
    document2 = "{ productsManufacturer(id: \"1\") { name products { name } } }"

    plan1 = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL::Stitching::Document.new(document1),
    ).perform

    plan2 = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL::Stitching::Document.new(document2),
    ).perform

    assert_equal 2, plan1.operations.length
    assert_equal 1, plan2.operations.length

    p1_first = plan1.operations[0]
    assert_equal "manufacturers", p1_first.location
    assert_equal "query", p1_first.operation_type
    assert_equal [], p1_first.insertion_path
    assert_equal "{ manufacturer(id: \"1\") { name _STITCH_id: id } }", p1_first.selection_set
    assert_nil p1_first.boundary
    assert_nil p1_first.after_key

    p1_second = plan1.operations[1]
    assert_equal "products", p1_second.location
    assert_equal "query", p1_second.operation_type
    assert_equal ["manufacturer"], p1_second.insertion_path
    assert_equal "{ products { name } }", p1_second.selection_set
    assert_equal p1_first.key, p1_second.after_key
    assert_equal "productsManufacturer", p1_second.boundary["field"]
    assert_equal "id", p1_second.boundary["selection"]

    p2_first = plan2.operations[0]
    assert_equal "products", p2_first.location
    assert_equal "query", p2_first.operation_type
    assert_equal [], p2_first.insertion_path
    assert_equal "{ productsManufacturer(id: \"1\") { name products { name } } }", p2_first.selection_set
    assert_nil p2_first.boundary
    assert_nil p2_first.after_key
  end

  def test_expands_selections_targeting_interface_locations
    a = "
      type Apple { id:ID! name:String }
      type Query { apple(id:ID!):Apple @boundary(key:\"id\") }
    "
    b = "
      interface Node { id:ID! }
      type Apple implements Node { id:ID! weight:Int }
      type Banana implements Node { id:ID! weight:Int }
      type Query { node(id:ID!):Node @boundary(key:\"id\") }
    "
    supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL::Stitching::Document.new("{ apple(id:\"1\") { id name weight } }"),
    ).perform

    first = plan.operations[0]
    assert_equal "a", first.location
    assert_equal [], first.insertion_path
    assert_equal "{ apple(id: \"1\") { id name _STITCH_id: id } }", first.selection_set
    assert_nil first.boundary
    assert_nil first.after_key

    second = plan.operations[1]
    assert_equal "b", second.location
    assert_equal ["apple"], second.insertion_path
    assert_equal "{ ... on Apple { weight } }", second.selection_set
    assert_equal "node", second.boundary["field"]
    assert_equal "id", second.boundary["selection"]
    assert_equal first.key, second.after_key
  end

  def test_expands_selections_targeting_union_locations
    a = "
      type Apple { id:ID! name:String }
      type Query { apple(id:ID!):Apple @boundary(key:\"id\") }
    "
    b = "
      type Apple { id:ID! weight:Int }
      type Banana { id:ID! weight:Int }
      union Node = Apple | Banana
      type Query { node(id:ID!):Node @boundary(key:\"id\") }
    "
    supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL::Stitching::Document.new("{ apple(id:\"1\") { id name weight } }"),
    ).perform

    first = plan.operations[0]
    assert_equal "a", first.location
    assert_equal [], first.insertion_path
    assert_equal "{ apple(id: \"1\") { id name _STITCH_id: id } }", first.selection_set
    assert_nil first.boundary
    assert_nil first.after_key

    second = plan.operations[1]
    assert_equal "b", second.location
    assert_equal ["apple"], second.insertion_path
    assert_equal "{ ... on Apple { weight } }", second.selection_set
    assert_equal "node", second.boundary["field"]
    assert_equal "id", second.boundary["selection"]
    assert_equal first.key, second.after_key
  end

  def test_expands_selections_for_abstracts_targeting_abstract_locations
    a = "
      interface Node { id:ID! }
      type Apple implements Node { id:ID! name:String }
      type Query { node(id:ID!):Node @boundary(key:\"id\") }
    "
    b = "
      type Apple { id:ID! weight:Int }
      type Banana { id:ID! weight:Int }
      union Fruit = Apple | Banana
      type Query { fruit(id:ID!):Fruit @boundary(key:\"id\") }
    "
    supergraph = compose_definitions({ "a" => a, "b" => b })

    plan = GraphQL::Stitching::Planner.new(
      supergraph: supergraph,
      document: GraphQL::Stitching::Document.new("{ node(id:\"1\") { id ...on Apple { name weight } } }"),
    ).perform

    first = plan.operations[0]
    assert_equal "a", first.location
    assert_equal [], first.insertion_path
    assert_equal "{ node(id: \"1\") { id ... on Apple { name _STITCH_id: id } _STITCH_typename: __typename } }", first.selection_set
    assert_nil first.boundary
    assert_nil first.after_key

    second = plan.operations[1]
    assert_equal "b", second.location
    assert_equal ["node"], second.insertion_path
    assert_equal "{ ... on Apple { weight } }", second.selection_set
    assert_equal "fruit", second.boundary["field"]
    assert_equal "id", second.boundary["selection"]
    assert_equal first.key, second.after_key
  end
end
