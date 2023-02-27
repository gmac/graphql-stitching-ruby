# frozen_string_literal: true

require 'rake/testtask'
require 'json'
require 'graphql'
require 'graphql/stitching'
require_relative './example_shopify/local_schema.rb'

Rake::TestTask.new(:test) do |t, args|
  puts args
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :build do |t|
  puts "filtering admin schema..."
  filtered_admin_schema = %x(node ./example_shopify/schemas/filter.js)

  puts "composing supergraph..."
  supergraph = GraphQL::Stitching::Composer.new.perform({
    admin: {
      schema: GraphQL::Schema.from_definition(filtered_admin_schema),
      stitch: [{ field_name: "product", key: "id" }],
    },
    local: {
      schema: MyBrandsSchema,
    },
  })

  puts "exporting..."
  supergraph_sdl, supergraph_map = supergraph.export
  File.write("example_shopify/schemas/supergraph.graphql", supergraph_sdl)
  File.write("example_shopify/schemas/supergraph.json", JSON.generate(supergraph_map))

  puts "done."
end

task :default => :test