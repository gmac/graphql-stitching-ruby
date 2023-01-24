# frozen_string_literal: true

require "test_helper"
require_relative "test_schema/basic"

describe 'Compose Test' do
  before do
    nil
  end

  it 'works' do
    schema, delegation_map = GraphQL::Stitching::Compose.new(schemas: {
      "products" => TestSchema::Basic::Products,
      "storefronts" => TestSchema::Basic::Storefronts,
      "manufacturers" => TestSchema::Basic::Manufacturers,
    }).compose

    puts GraphQL::Schema::Printer.print_schema(schema)
    byebug
  end
end
