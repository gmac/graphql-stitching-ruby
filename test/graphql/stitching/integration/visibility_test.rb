# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/visibility"

describe 'GraphQL::Stitching, visibility' do
  def setup
    @supergraph = compose_definitions({
      "a" => Schemas::Visibility::Alpha,
      "b" => Schemas::Visibility::Bravo,
    })
  end

  # def test_grants_field_visibility_by_single_schema_permission
  #   query = %|{ thingA(id: "1") { id size } }|

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: [])
  #   assert_validation_error(request, "undefinedField")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a"])
  #   assert_no_validation_errors(request)
  # end

  # def test_grants_field_visibility_by_joint_schema_permission
  #   query = %|{ thingA(id: "1") { id color } }|

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a"])
  #   assert_validation_error(request, "undefinedField")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["b"])
  #   assert_validation_error(request, "undefinedField")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a", "b"])
  #   assert_no_validation_errors(request)
  # end

  # def test_grants_field_visibility_by_alternate_schema_permissions
  #   query = %|{ thingA(id: "1") { id color } }|

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: [])
  #   assert_validation_error(request, "undefinedField")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a", "b"])
  #   assert_no_validation_errors(request)

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["c"])
  #   assert_no_validation_errors(request)
  # end

  # def test_grants_type_visibility_joint_schema_permissions
  #   query = %|{ widgetA{ id } }|

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: [])
  #   assert_validation_error(request, "undefinedField")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a"])
  #   assert_validation_error(request, "undefinedField")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["b"])
  #   assert_validation_error(request, "undefinedField")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a", "b"])
  #   assert_no_validation_errors(request)
  # end

  # def test_grants_argument_visibility_joint_schema_permissions
  #   query = %|{ args(id: "123") }|

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: [])
  #   assert_validation_error(request, "argumentNotAccepted")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a"])
  #   assert_validation_error(request, "argumentNotAccepted")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["b"])
  #   assert_validation_error(request, "argumentNotAccepted")

  #   request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a", "b"])
  #   assert_no_validation_errors(request)
  # end

  def test_grants_enum_value_visibility_joint_schema_permissions
    query = %|{ args(enum: "MAYBE") }|

    request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: [])
    assert_validation_error(request, "argumentLiteralsIncompatible")

    request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a"])
    assert_validation_error(request, "argumentLiteralsIncompatible")

    request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["b"])
    assert_validation_error(request, "argumentLiteralsIncompatible")

    request = GraphQL::Stitching::Request.new(@supergraph, query, visibility_claims: ["a", "b"])
    puts request.validate.first.message
    assert_no_validation_errors(request)
  end

  private

  def assert_validation_error(request, code)
    errors = request.validate
    assert errors.any?, "expected a validation error"
    assert_equal code, errors.first.code
  end

  def assert_no_validation_errors(request)
    errors = request.validate
    assert errors.none?, "expected no validation errors"
  end
end
