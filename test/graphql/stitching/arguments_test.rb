# frozen_string_literal: true

require "test_helper"

class GraphQL::Stitching::ArgumentsTest < Minitest::Test
  class TestSchema < GraphQL::Schema
    class TestEnum < GraphQL::Schema::Enum
      value "YES"
    end

    class ObjectKey < GraphQL::Schema::InputObject
      graphql_name "ObjectKey"

      argument :namespace, String, required: true
      argument :key, String, required: true
      argument :owner_type, String, required: false
      argument :owner_id, String, required: false
    end

    class OpaqueKey < GraphQL::Schema::Scalar
      graphql_name "OpaqueKey"
    end

    class Query < GraphQL::Schema::Object
      field :object_key, Boolean, null: false do |f|
        f.argument(:key, ObjectKey)
      end

      field :object_list_key, Boolean, null: false do |f|
        f.argument(:keys, [ObjectKey])
      end
    end

    query Query
  end

  def test_is_leaf_type
    args_schema = TestSchema.query.get_field("objectListKey").arguments
    template = "key: {namespace: $.namespace, key: $.key, ownerType: $.ref.__typename, ownerId: $.ref.id}"
    binding.pry
    puts GraphQL::Stitching::Arguments.parse(args_schema, template)
  end
end
