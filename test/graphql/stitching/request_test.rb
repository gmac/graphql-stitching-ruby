# frozen_string_literal: true

require "test_helper"
require_relative "../../schemas/example"

describe "GraphQL::Stitching::Request" do
  def setup
    @supergraph = GraphQL::Stitching::Supergraph.new(
      schema: Schemas::Example::Products,
      fields: {},
      boundaries: {},
      executables: {},
    )
  end

  def test_builds_with_pre_parsed_ast
    ast = GraphQL.parse("query First { widget { id } }")
    request = GraphQL::Stitching::Request.new(@supergraph, ast)

    assert_equal "query", request.operation.operation_type
    assert_equal "widget", request.operation.selections.first.name
  end

  def test_selects_single_operation_by_default
    request = GraphQL::Stitching::Request.new(
      @supergraph,
      "query First { widget { id } }",
    )

    assert_equal "query", request.operation.operation_type
    assert_equal "widget", request.operation.selections.first.name
  end

  def test_selects_from_multiple_operations_by_operation_name
    query = %|
      query First { widget { id } }
      query Second { sprocket { id } }
      mutation Third { makeSprocket(id: "1") { id } }
    |
    request1 = GraphQL::Stitching::Request.new(@supergraph, query, operation_name: "First")
    request2 = GraphQL::Stitching::Request.new(@supergraph, query, operation_name: "Second")
    request3 = GraphQL::Stitching::Request.new(@supergraph, query, operation_name: "Third")

    assert_equal "query", request1.operation.operation_type
    assert_equal "query", request2.operation.operation_type
    assert_equal "mutation", request3.operation.operation_type

    assert_equal "widget", request1.operation.selections.first.name
    assert_equal "sprocket", request2.operation.selections.first.name
  end

  def test_operation_errors_for_multiple_operations_given_without_operation_name
    query = "query First { widget { id } } query Second { sprocket { id } }"

    assert_error "An operation name is required", GraphQL::ExecutionError do
      GraphQL::Stitching::Request.new(@supergraph, query).operation
    end
  end

  def test_operation_errors_for_invalid_operation_names
    query = "query First { widget { id } } query Second { sprocket { id } }"

    assert_error "Invalid root operation", GraphQL::ExecutionError do
      GraphQL::Stitching::Request.new(@supergraph, query, operation_name: "Invalid").operation
    end
  end

  def test_operation_errors_for_invalid_operation_types
    assert_error "Invalid root operation", GraphQL::ExecutionError do
      GraphQL::Stitching::Request.new(@supergraph, "subscription { movie }").operation
    end
  end

  def test_access_operation_directives
    query = %|
      query First @inContext(lang: "EN") { widget { id } }
      mutation Second @alpha(a: 1) @bravo(b: true) { makeSprocket(id: "1") { id } }
    |

    request1 = GraphQL::Stitching::Request.new(@supergraph, query, operation_name: "First")
    request2 = GraphQL::Stitching::Request.new(@supergraph, query, operation_name: "Second")

    assert_equal %|@inContext(lang: "EN")|, request1.operation_directives
    assert_equal %|@alpha(a: 1) @bravo(b: true)|, request2.operation_directives
  end

  def test_accesses_document_variable_definitions
    query = %|
      query($ids: [ID!]!, $ns: String!, $lang: String) {
        widget(ids: $ids, ns: $ns) { id name(lang: $lang) }
      }
    |
    request = GraphQL::Stitching::Request.new(@supergraph, query)
    variables = request.variable_definitions.each_with_object({}) do |(name, type), memo|
      memo[name] = GraphQL::Language::Printer.new.print(type)
    end

    expected = {
      "ids" => "[ID!]!",
      "ns" => "String!",
      "lang" => "String",
    }

    assert_equal expected, variables
  end

  def test_accesses_document_fragment_definitions
    query = %|
      query { things { ...WidgetAttrs ...SprocketAttrs } }
      fragment WidgetAttrs on Widget { widget }
      fragment SprocketAttrs on Sprocket { sprocket }
    |
    request = GraphQL::Stitching::Request.new(@supergraph, query)

    assert_equal "widget", request.fragment_definitions["WidgetAttrs"].selections.first.name
    assert_equal "sprocket", request.fragment_definitions["SprocketAttrs"].selections.first.name
  end

  def test_provides_string_and_normalized_string
    string = %|
      query {
        things { name }
      }
    |

    request = GraphQL::Stitching::Request.new(@supergraph, string)
    assert_equal string, request.string
    assert_equal GraphQL.parse(string).to_query_string, request.normalized_string
  end

  def test_provides_string_and_normalized_string_for_parsed_ast_input
    document = GraphQL.parse("query { things { name } }")
    request = GraphQL::Stitching::Request.new(@supergraph, document)
    expected = document.to_query_string

    assert_equal expected, request.string
    assert_equal expected, request.normalized_string
  end

  def test_provides_digest_and_normalized_digest
    string = %|
      query {
        things { name }
      }
    |

    request = GraphQL::Stitching::Request.new(@supergraph, string)
    expected = "ad4b4eb706f67020084a7927ed5bd73b7196e393e0af3535d25ae2d22df33232"
    expected_normalized = "88908d0790f7b20afe4a7508a8bba6343c62f98abb9c5abff17345c64d90c0d0"

    assert_equal expected, request.digest
    assert_equal expected_normalized, request.normalized_digest
  end

  def test_prepare_variables_collects_variable_defaults
    query = %|
      query($a: String! = "defaultA", $b: String! = "defaultB") {
        base(a: $a, b: $b) { id }
      }
    |

    request = GraphQL::Stitching::Request.new(@supergraph, GraphQL.parse(query), variables: { "a" => "yes" })
    request.prepare!

    expected = { "a" => "yes", "b" => "defaultB" }
    assert_equal expected, request.variables
  end

  def test_prepare_variables_preserves_boolean_values
    query = %|
      query($a: Boolean, $b: Boolean, $c: Boolean = true) {
        base(a: $a, b: $b, c: $c) { id }
      }
    |

    variables = { "a" => true, "b" => false, "c" => false }
    request = GraphQL::Stitching::Request.new(@supergraph, GraphQL.parse(query), variables: variables)
    request.prepare!

    expected = { "a" => true, "b" => false, "c" => false }
    assert_equal expected, request.variables
  end

  def test_prepare_variables_does_not_add_null_keys
    query = %|
      query($a: Boolean, $b: Boolean = false) {
        base(a: $a, b: $b) { id }
      }
    |

    variables = {}
    request = GraphQL::Stitching::Request.new(@supergraph, GraphQL.parse(query), variables: variables)
    request.prepare!

    expected = { "b" => false }
    assert_equal expected, request.variables
  end

  def test_applies_skip_and_include_directives_via_boolean_literals
    query = %|
      query {
        skipKeep @skip(if: false) { id }
        skipOmit @skip(if: true) { id }
        includeKeep @include(if: true) { id }
        includeOmit @include(if: false) { id }
      }
    |

    request = GraphQL::Stitching::Request.new(@supergraph, GraphQL.parse(query))
    request.prepare!

    assert_equal "query { skipKeep { id } includeKeep { id } }", squish_string(request.document.to_query_string)
  end

  def test_applies_skip_and_include_directives_via_variables
    query = %|
      query($yes: Boolean!, $no: Boolean!) {
        skipKeep @skip(if: $no) { id }
        skipOmit @skip(if: $yes) { id }
        includeKeep @include(if: $yes) { id }
        includeOmit @include(if: $no) { id }
      }
    |

    request = GraphQL::Stitching::Request.new(@supergraph, GraphQL.parse(query), variables: {
      "yes" => true,
      "no" => false,
    })
    request.prepare!

    expected = "query($yes: Boolean!, $no: Boolean!) { skipKeep { id } includeKeep { id } }"
    assert_equal expected, squish_string(request.document.to_query_string)
  end

  def test_validates_the_request
    request1 = GraphQL::Stitching::Request.new(@supergraph, %|{ product(upc: "1") { upc} }|)
    assert request1.validate.none?

    request2 = GraphQL::Stitching::Request.new(@supergraph, %|{ invalidSelection }|)
    assert_equal 1, request2.validate.length
  end

  def test_assigns_a_plan_for_the_request
    plan = GraphQL::Stitching::Plan.new(ops: [])
    request = GraphQL::Stitching::Request.new(@supergraph, "{ widget { id } }")

    request.plan(plan)
    assert_equal plan.object_id, request.plan.object_id
  end

  def test_assigning_a_plan_must_be_plan_instance
    request = GraphQL::Stitching::Request.new(@supergraph, "{ widget { id } }")

    assert_error "Plan must be a `GraphQL::Stitching::Plan`", GraphQL::Stitching::StitchingError do
      request.plan({})
    end
  end
end
