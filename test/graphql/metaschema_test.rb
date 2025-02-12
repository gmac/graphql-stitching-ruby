# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Metaschemas" do
  class MetaschemaBuilder
    def initialize
      @meta_types = JSON.parse(File.read("#{__dir__}/metaschema/metaschema.json"))
      @admin_schema = GraphQL::Schema.from_definition(File.read("#{__dir__}/metaschema/admin_2025_01_public.graphql"))

      introspection_names = @admin_schema.introspection_system.types.keys
      @schema_types = @admin_schema.types.reject! { |k, v| introspection_names.include?(k) }
      @metaobjects_by_id = @meta_types.dig("data", "metaobjectDefinitions", "nodes").each_with_object({}) do |obj, memo|
        obj.delete("metaobjects")
        memo[obj["id"]] = obj
      end
    end

    def perform
      product_metafields = @meta_types.dig("data", "productFields", "nodes")

      if product_metafields.any?
        builder = self
        name = "ProductExtensions"
        ext_type = Class.new(GraphQL::Schema::Object) do
          graphql_name(name)
          description("Metafield extensions of the Product type.")

          product_metafields.each do |f|
            field(
              f["key"].to_sym,
              builder.type_for_field(f.dig("type", "name"), f["validations"]),
              description: f["description"],
            )
          end
        end

        @schema_types[name] = ext_type
        @schema_types["Product"].field :extensions, ext_type, null: false, description: "Metafield extensions on the Product type."
      end

      types = @schema_types
      new_schema = Class.new(GraphQL::Schema) do
        add_type_and_traverse(types.values, root: false)
        orphan_types(types.values.select { |t| t.respond_to?(:kind) && t.kind.object? })
        query types["QueryRoot"]
        own_orphan_types.clear
      end

      File.write("#{__dir__}/metaschema/admin_meta_2025_01_public.graphql", new_schema.to_definition)
    end

    def type_for_field(type, validations)
      case type
      when "single_line_text_field"
        GraphQL::Schema::BUILT_IN_TYPES["String"]
      when "number_integer"
        GraphQL::Schema::BUILT_IN_TYPES["Int"]
      when "number_decimal"
        GraphQL::Schema::BUILT_IN_TYPES["Float"]
      when "product_reference"
        @schema_types["Product"]
      when "list.product_reference"
        @schema_types["ProductConnection"]
      when "metaobject_reference"
        metaobject_id = validations.find { _1["name"] == "metaobject_definition_id" }["value"]
        metaobject_def = @metaobjects_by_id[metaobject_id]
        GraphQL::Schema::BUILT_IN_TYPES["String"]
      else
        GraphQL::Schema::BUILT_IN_TYPES["String"]
      end
    end

    def metaobject_type()

    end
  end

  def test_go
    MetaschemaBuilder.new.perform
    assert true
  end
end
