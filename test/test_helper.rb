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
require 'minitest/stub_const'
require 'graphql/stitching'

CompositionError = GraphQL::Stitching::CompositionError
ValidationError = GraphQL::Stitching::ValidationError
STITCH_DEFINITION = "directive @stitch(key: String!, arguments: String, typeName: String) repeatable on FIELD_DEFINITION\n"
VISIBILITY_DEFINITION = "directive @visibility(profiles: [String!]!) on ARGUMENT_DEFINITION | ENUM | ENUM_VALUE | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | INPUT_OBJECT | INTERFACE | OBJECT | SCALAR | UNION\n"

class Matcher
  def match?(value)
    true
  end
end

class SortedSelectionMatcher < Matcher
  NODE_ORDER = [
    GraphQL::Language::Nodes::Field, 
    GraphQL::Language::Nodes::InlineFragment, 
    GraphQL::Language::Nodes::FragmentSpread,
  ].freeze

  attr_reader :source

  def initialize(source)
    @printer = GraphQL::Language::Printer.new
    source = GraphQL.parse(source) if source.is_a?(String)
    source = sort_node_selections(source.definitions.first)
    @source = @printer.print(source)
  end

  def match?(other)
    other = GraphQL.parse(other) if other.is_a?(String)
    other = sort_node_selections(other.definitions.first)
    @source == @printer.print(other)
  end

  private

  def sort_node_selections(node)
    selections = node.selections.sort do |a, b|
      if a.class == b.class
        case a
        when GraphQL::Language::Nodes::Field
          an = [a.alias, a.name].tap(&:compact!).join("-")
          bn = [b.alias, b.name].tap(&:compact!).join("-")
          an <=> bn
        when GraphQL::Language::Nodes::InlineFragment
          (a.type&.name).to_s <=> (b.type&.name).to_s
        when GraphQL::Language::Nodes::FragmentSpread
          a.name <=> b.name
        end
      else
        NODE_ORDER.index(a.class) - NODE_ORDER.index(b.class)
      end
    end

    selections = selections.map do |node|
      next node unless node.respond_to?(:selections) && node.selections.any?
      
      sort_node_selections(node)
    end

    node.merge(selections: selections)
  end
end

class TestFormatter
  include GraphQL::Stitching::Formatter

  def merge_values(values_by_location, _info)
    vals = values_by_location.each_value.reject(&:nil?)
    vals.empty? ? nil : vals.join("/")
  end

  def merge_default_values(values_by_location, _info)
    values_by_location.values.max
  end
end

def squish_string(str)
  str.gsub(/\s+/, " ").strip
end

def minimum_graphql_version?(versioning)
  Gem::Version.new(GraphQL::VERSION) >= Gem::Version.new(versioning)
end

def compose_definitions(locations, options={})
  locations = locations.each_with_object({}) do |(location, schema_config), memo|
    memo[location.to_s] = if schema_config.is_a?(Hash)
      schema_config
    elsif schema_config.is_a?(String)
      schema_config = STITCH_DEFINITION + schema_config if schema_config.include?("@stitch")
      { schema: GraphQL::Schema.from_definition(schema_config) }
    else
      { schema: schema_config }
    end
  end
  composer = GraphQL::Stitching::Composer.new(**options)
  supergraph = composer.perform(locations)
  yield(composer, supergraph) if block_given?
  supergraph
end

def supergraph_from_schema(schema, fields: {}, resolvers: {}, executables: {})
  GraphQL::Stitching::Supergraph.new(
    schema: schema.is_a?(String) ? GraphQL::Schema.from_definition(schema) : schema,
    fields: fields,
    resolvers: resolvers,
    executables: executables,
  )
end

def plan_and_execute(supergraph, query, variables={}, raw: false)
  request = GraphQL::Stitching::Request.new(
    supergraph,
    query,
    variables: variables,
  )

  assert request.valid?, "Expected request to be valid: #{request.validate.map(&:message)}"
  plan = request.plan
  executor = GraphQL::Stitching::Executor.new(request)
  result = executor.perform(raw: raw)

  yield(plan, executor) if block_given?
  result
end

def extract_types_of_kind(schema, kind)
  schema.types.values.select { _1.kind.object? && !_1.graphql_name.start_with?("__") }
end

def with_static_resolver_version
  GraphQL::Stitching::TypeResolver.instance_variable_set(:@use_static_version, true)
  yield
ensure
  GraphQL::Stitching::TypeResolver.instance_variable_set(:@use_static_version, false)
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
    elsif ex_val.is_a?(Matcher)
      assert ex_val.match?(val)
    elsif ex_val.nil?
      assert_nil val
    else
      assert_equal ex_val, val
    end
  end
end
