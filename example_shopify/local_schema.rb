BRANDS = [
  { id: "1", name: "Lego" },
  { id: "2", name: "McTesting" },
]

PRODUCTS_REL_BRANDS = [
  ["gid://shopify/Product/6885875646486", "1"],
  ["gid://shopify/Product/6561850556438", "1"],
  ["gid://shopify/Product/6561850785814", "1"],
  ["gid://shopify/Product/6561850884118", "1"],
  ["gid://shopify/Product/7501637156886", "2"],
]

class MyBrandsSchema < GraphQL::Schema
  class StitchField < GraphQL::Schema::Directive
    graphql_name "stitch"
    locations FIELD_DEFINITION
    argument :key, String
    repeatable true
  end

  class Brand < GraphQL::Schema::Object
    field :id, ID, null: false
    field :name, String, null: false
    field :products, ["MyBrandsSchema::Product"], null: false

    def products
      PRODUCTS_REL_BRANDS
        .select { |rel| rel[1] == object[:id] }
        .map { |rel| { id: rel[0] } }
    end
  end

  class Product < GraphQL::Schema::Object
    field :id, ID, null: false
    field :brands, [Brand], null: false

    def brands
      PRODUCTS_REL_BRANDS
        .select { |rel| rel[0] == object[:id] }
        .map { |rel| BRANDS.find { rel[1] == _1[:id] } }
    end
  end

  class Query < GraphQL::Schema::Object
    field :brands, [Brand, null: true], null: false do
      argument :ids, [ID], required: true
    end

    def brands(ids:)
      ids.map { |id| BRANDS.find { _1[:id] == id } }
    end

    field :brand_products, [Product, null: true], null: false do
      directive StitchField, key: "id"
      argument :ids, [ID], required: true
    end

    def brand_products(ids:)
      product_ids = PRODUCTS_REL_BRANDS.map { _1[0] }
      (product_ids & ids).map { |id| { id: id } }
    end
  end

  query Query
end
