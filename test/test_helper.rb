# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'warning'
Gem.path.each do |path|
  # ignore warnings from auto-generated GraphQL lib code.
  Warning.ignore(/.*mismatched indentations.*/)
end

require 'bundler/setup'
Bundler.require(:default, :test)

require 'minitest/pride'
require 'minitest/autorun'
require 'graphql/stitching'

def compose_definitions(schemas, options={})
  schemas = schemas.each_with_object({}) do |(location, schema_or_sdl), memo|
    memo[location] = if schema_or_sdl.is_a?(String)
      boundary = "directive @boundary(key: String!) repeatable on FIELD_DEFINITION\n"
      schema_or_sdl = boundary + schema_or_sdl if schema_or_sdl.include?("@boundary")
      GraphQL::Schema.from_definition(schema_or_sdl)
    else
      schema_or_sdl
    end
  end
  GraphQL::Stitching::Composer.new(schemas: schemas, **options).perform
end

def extract_types_of_kind(schema, kind)
  schema.types.values.select { _1.kind.object? && !_1.graphql_name.start_with?("__") }
end

# prints a wrapped field/argument value type as GraphQL SDL
def print_value_type(type)
  base_name = GraphQL::Stitching::Util.get_named_type(type).graphql_name
  wrappers = []

  while type.respond_to?(:of_type)
    if type.is_a?(GraphQL::Schema::NonNull)
      wrappers << :non_null
    elsif type.is_a?(GraphQL::Schema::List)
      wrappers << :list
    end
    type = type.of_type
  end

  wrappers.reverse!.reduce(base_name) do |memo, wrapper|
    case wrapper
    when :non_null
      "#{memo}!"
    when :list
      "[#{memo}]"
    end
  end
end

ComposerError = GraphQL::Stitching::Composer::ComposerError
ValidationError = GraphQL::Stitching::Composer::ValidationError

def assert_error(pattern, klass=nil)
  begin
    yield
  rescue StandardError => e
    if pattern.is_a?(String)
      assert e.message.include?(pattern), "Unexpected error message: #{e.message}"
    else
      assert pattern.match?(e.message), "Unexpected error message: #{e.message}"
    end
    assert e.is_a?(klass), "Unexpected error type #{klass.name}" if klass
  end
end
