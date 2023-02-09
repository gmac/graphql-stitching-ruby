# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Shaper
      def initialize(supergraph:, document:, raw:)
        @supergraph = supergraph
        @document = document
        @result = raw
        @errors = []
      end

      def perform!
        if @result.key?("data") && ! @result["data"].empty?
          munge_entry(@result["data"], @document.operation.selections, @supergraph.schema.query)
          # hate doing a second pass, but cannot remove _STITCH_ fields until the fragements are processed
          clean_entry(@result["data"])
        end

        if @errors.length > 0
          @result = [] unless @result.key?("errors")
          @result["errors"] += @errors
        end

        @result
      end

      private

      def munge_entry(entry, selections, parent_type)
        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            next if node.respond_to?(:name) && node&.name == "__typename"

            munge_field(entry, node, parent_type)

          when GraphQL::Language::Nodes::InlineFragment
            next unless entry["_STITCH_typename"] == node.type.name
            fragment_type = @supergraph.schema.types[node.type.name]
            munge_entry(entry, node.selections, fragment_type)

          when GraphQL::Language::Nodes::FragmentSpread
            next unless entry["_STITCH_typename"] == node.name
            fragment = @document.fragment_definitions[node.name]
            fragment_type = @supergraph.schema.types[node.name]
            munge_entry(entry, fragment.selections, fragment_type)
          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end
      end

      def munge_field(entry, node, parent_type)
        field_identifier = (node.alias || node.name)
        node_type = Util.get_named_type_for_field_node(@supergraph.schema, parent_type, node)

        if entry.nil?
          return  # TODO bubble up error if not nullable
        end

        child_entry = entry[field_identifier]
        if child_entry.nil?
          entry[field_identifier] = nil
        elsif child_entry.is_a? Array
          child_entry.each do |raw_item|
            munge_entry(raw_item, node.selections, node_type)
          end
        elsif ! Util.is_leaf_type?(node_type)
          munge_entry(child_entry, node.selections, node_type)
        end
      end

      def clean_entry(entry)
        return if entry.nil?

        entry.each do |key, value|
          if key.start_with? "_STITCH_"
            entry.delete(key)
          elsif value.is_a?(Array)
            value.each do |item|
              clean_entry(item)
            end
          elsif value.is_a?(Hash)
            clean_entry(value)
          end
        end
      end
    end
  end
end
