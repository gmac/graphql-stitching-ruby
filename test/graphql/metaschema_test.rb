# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Metaschemas" do
  class MetaschemaComposer
    def initialize
      @meta_types = JSON.parse(File.read("#{__dir__}/metaschema/metaschema.json"))
      @admin_schema = GraphQL::Schema.from_definition(File.read("#{__dir__}/metaschema/admin_2025_01_public.graphql"))

      introspection_names = @admin_schema.introspection_system.types.keys
      @schema_types = @admin_schema.types.reject! { |k, v| introspection_names.include?(k) }
      @metaobject_definitions_by_id = @meta_types.dig("data", "metaobjectDefinitions", "nodes").each_with_object({}) do |obj, memo|
        obj.delete("metaobjects")
        memo[obj["id"]] = obj
      end
    end

    def perform
      @admin_schema.possible_types(@schema_types["HasMetafields"]).each do |native_type|
        build_native_type_extensions(native_type)
      end

      @metaobject_definitions_by_id.each_value do |metaobject_def|
        build_metaobject(metaobject_def)
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

    FIXME_MISSING_TYPE = GraphQL::Schema::BUILT_IN_TYPES["Boolean"]

    def type_for_metafield_definition(field_def)
      metafield_type = field_def.dig("type", "name")
      list = metafield_type.start_with?("list")
      case metafield_type
      when "boolean"
        @schema_types["Boolean"]
      when "color", "list.color"
        type = @schema_types["ColorMetatype"] || build_color_metatype
        list ? type.to_list_type : type
      when "collection_reference", "list.collection_reference"
        list ? @schema_types["CollectionConnection"] : @schema_types["Collection"]
      when "company_reference", "list.company_reference"
        list ? @schema_types["CompanyConnection"] : @schema_types["Company"]
      when "customer_reference", "list.customer_reference"
        list ? @schema_types["CustomerConnection"] : @schema_types["Customer"]
      when "date_time", "list.date_time"
        type = @schema_types["DateTime"]
        list ? type.to_list_type : type
      when "date", "list.date"
        type = @schema_types["Date"]
        list ? type.to_list_type : type
      when "dimension", "list.dimension"
        type = @schema_types["DimensionMetatype"] || build_dimension_metatype
        list ? type.to_list_type : type
      when "file_reference", "list.file_reference"
        FIXME_MISSING_TYPE
      when "id"
        @schema_types["ID"]
      when "json"
        @schema_types["JSON"]
      when "language"
        @schema_types["LanguageCode"]
      when "link", "list.link"
        type = @schema_types["Link"]
        list ? type.to_list_type : type
      when "metaobject_reference", "list.metaobject_reference"
        metaobject_id = field_def["validations"].find { _1["name"] == "metaobject_definition_id" }["value"]
        metaobject_def = @metaobject_definitions_by_id[metaobject_id]
        if metaobject_def
          metaobject_name = name_for_metaobject(metaobject_def)
          GraphQL::Schema::LateBoundType.new(list ? "#{metaobject_name}Connection" : metaobject_name)
        else
          raise "invalid metaobject_reference for #{field_def["key"]}"
        end
      when "mixed_reference", "list.mixed_reference"
        FIXME_MISSING_TYPE
      when "money"
        @schema_types["MoneyV2"]
      when "multi_line_text_field"
        @schema_types["String"]
      when "number_decimal", "list.number_decimal"
        type = @schema_types["Float"]
        list ? type.to_list_type : type
      when "number_integer", "list.number_integer"
        type = @schema_types["Int"]
        list ? type.to_list_type : type
      when "order_reference"
        @schema_types["Order"]
      when "page_reference", "list.page_reference"
        list ? @schema_types["PageConnection"] : @schema_types["Page"]
      when "product_reference", "list.product_reference"
        list ? @schema_types["ProductConnection"] : @schema_types["Product"]
      when "product_taxonomy_value_reference", "list.product_taxonomy_value_reference"
        list ? @schema_types["TaxonomyValueConnection"] : @schema_types["TaxonomyValue"]
      when "rating", "list.rating"
        type = @schema_types["RatingMetatype"] || build_rating_metatype
        list ? type.to_list_type : type
      when "rich_text_field"
        FIXME_MISSING_TYPE
      when "single_line_text_field", "list.single_line_text_field"
        type = @schema_types["String"]
        list ? type.to_list_type : type
      when "url", "list.url"
        type = @schema_types["URL"]
        list ? type.to_list_type : type
      when "variant_reference", "list.variant_reference"
        list ? @schema_types["ProductVariantConnection"] : @schema_types["ProductVariant"]
      when "volume", "list.volume"
        type = @schema_types["VolumeMetatype"] || build_volume_metatype
        list ? type.to_list_type : type
      when "weight", "list.weight"
        type = @schema_types["Weight"]
        list ? type.to_list_type : type
      else
        raise "Unknown metafield type `#{metafield_type}`"
      end
    end

    def name_for_metaobject(metaobject_def)
      name = metaobject_def["type"]
      name[0] = name[0].upcase
      name.gsub!(/_\w/) { _1[1].upcase }
      "#{name}Metaobject"
    end

    def build_native_type_extensions(native_type)
      metafield_definitions = @meta_types.dig("data", "#{native_type.graphql_name.downcase}Fields", "nodes")
      return unless metafield_definitions&.any?

      builder = self
      extensions_type_name = "#{native_type.graphql_name}Extensions"
      type = @schema_types[extensions_type_name] = Class.new(GraphQL::Schema::Object) do
        graphql_name(extensions_type_name)
        description("Projected metafield extensions for the #{native_type.graphql_name} type.")

        metafield_definitions.each do |metafield_def|
          builder.build_object_field(metafield_def, self)
        end
      end

      native_type.field(
        :extensions,
        type,
        null: false,
        description: "Projected metafield extensions.",
      )
    end

    def build_object_field(metafield_def, owner)
      type = type_for_metafield_definition(metafield_def)
      builder_types = @schema_types
      owner.field(
        metafield_def["key"].to_sym,
        type,
        description: metafield_def["description"],
        connection: false, # don't automatically build connection configuration
      ) do |f|
        if type.unwrap.graphql_name.end_with?("Connection")
          f.argument(:first, builder_types["Int"], required: false)
          f.argument(:last, builder_types["Int"], required: false)
          f.argument(:before, builder_types["String"], required: false)
          f.argument(:after, builder_types["String"], required: false)
        end
      end
    end

    def build_metaobject(metaobject_def)
      builder = self
      metaobject_type_name = name_for_metaobject(metaobject_def)
      metaobject_type = @schema_types[metaobject_type_name] = Class.new(GraphQL::Schema::Object) do
        graphql_name(metaobject_type_name)
        description(metaobject_def["description"])

        metaobject_def["fieldDefinitions"].each do |metafield_def|
          builder.build_object_field(metafield_def, self)
        end
      end

      page_info_type = @schema_types["PageInfo"]
      @schema_types[metaobject_type.edge_type.graphql_name] = metaobject_type.edge_type
      @schema_types["#{metaobject_type.graphql_name}Connection"] = Class.new(GraphQL::Schema::Object) do
        graphql_name("#{metaobject_type.graphql_name}Connection")
        field :edges, metaobject_type.edge_type.to_non_null_type.to_list_type, null: false
        field :nodes, metaobject_type.to_non_null_type.to_list_type, null: false
        field :page_info, page_info_type, null: false
      end
    end

    def build_color_metatype
      FIXME_MISSING_TYPE
    end

    def build_dimension_metatype
      FIXME_MISSING_TYPE
    end

    def build_rating_metatype
      FIXME_MISSING_TYPE
    end

    def build_volume_metatype
      FIXME_MISSING_TYPE
    end
  end

  def test_go
    MetaschemaComposer.new.perform
    assert true
  end
end
