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

def compose_definitions(schemas)
  schemas = schemas.each_with_object({}) do |(location, definition), memo|
    memo[location] = GraphQL::Schema.from_definition(definition)
  end
  GraphQL::Stitching::Compose.new(schemas: schemas).compose
end

def extract_types_of_kind(schema, kind)
  schema.types.values.select { _1.kind.name == "OBJECT" && !_1.graphql_name.start_with?("__") }
end

def print_type(type)
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