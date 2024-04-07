# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'warning'
Gem.path.each do |path|
  # ignore warnings from auto-generated GraphQL lib code.
  Warning.ignore(/.*mismatched indentations.*/)
  Warning.ignore(/.*lib\/graphql\/language\/nodes.rb:.*/)
end

require 'bundler/setup'
Bundler.require(:default, :test)

require 'minitest/pride'
require 'minitest/autorun'
require 'graphql/stitching'

ComposerError = GraphQL::Stitching::Composer::ComposerError
ValidationError = GraphQL::Stitching::Composer::ValidationError
STITCH_DEFINITION = "directive @stitch(key: String!, typeName: String, federation: Boolean=false) repeatable on FIELD_DEFINITION\n"

def squish_string(str)
  str.gsub(/\s+/, " ").strip
end

def minimum_graphql_version?(versioning)
  lib_versioning = GraphQL::VERSION.split(".").map(&:to_i)
  versioning.split(".").map(&:to_i).each_with_index.any? do |version, i|
    lib_version = lib_versioning[i] || 0
    if i == versioning.length - 1
      return lib_version >= version
    elsif lib_version > version
      return true
    end
  end
end

def compose_definitions(locations, options={})
  locations = locations.each_with_object({}) do |(location, schema_or_sdl), memo|
    schema = if schema_or_sdl.is_a?(String)
      schema_or_sdl = STITCH_DEFINITION + schema_or_sdl if schema_or_sdl.include?("@stitch")
      GraphQL::Schema.from_definition(schema_or_sdl)
    else
      schema_or_sdl
    end
    memo[location.to_s] = { schema: schema }
  end
  GraphQL::Stitching::Composer.new(**options).perform(locations)
end

def supergraph_from_schema(schema, fields: {}, boundaries: {}, executables: {})
  GraphQL::Stitching::Supergraph.new(
    schema: schema.is_a?(String) ? GraphQL::Schema.from_definition(schema) : schema,
    fields: fields,
    boundaries: boundaries,
    executables: executables,
  )
end

def plan_and_execute(supergraph, query, variables={}, raw: false)
  request = GraphQL::Stitching::Request.new(
    supergraph,
    query,
    variables: variables,
  )

  plan = request.plan
  executor = GraphQL::Stitching::Executor.new(request)
  result = executor.perform(raw: raw)

  yield(plan, executor) if block_given?
  result
end

def extract_types_of_kind(schema, kind)
  schema.types.values.select { _1.kind.object? && !_1.graphql_name.start_with?("__") }
end

def assert_error(pattern, klass=nil)
  begin
    yield
    flunk "No error was raised."
  rescue StandardError => e
    if pattern.is_a?(String)
      assert e.message.include?(pattern), "Unexpected error message: #{e.message}"
    else
      assert pattern.match?(e.message), "Unexpected error message: #{e.message}"
    end
    assert e.is_a?(klass), "Unexpected error type #{klass.name}" if klass
  end
end

def assert_keys(actual, expected)
  expected.each do |key, ex_val|
    val = actual[key]
    if ex_val.is_a?(Hash)
      assert val.is_a?(Hash), "expected a hash for #{key}"
      assert_keys(val, ex_val)
    elsif ex_val.nil?
      assert_nil val
    else
      assert_equal ex_val, val
    end
  end
end
