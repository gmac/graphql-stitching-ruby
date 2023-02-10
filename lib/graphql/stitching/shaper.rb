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
        @result["data"] = resolve_object_scope(@result["data"], @supergraph.schema.query, @document.operation.selections)
        @result
      end

      private

      def resolve_object_scope(raw_object, parent_type, selections, typename = nil)
        return nil unless raw_object

        typename ||= raw_object["_STITCH_typename"]
        raw_object.reject! { |k, _v| k.start_with?("_STITCH_") }

        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            next if node.name == "__typename"

            field_name = node.alias || node.name
            node_type = parent_type.fields[node.name].type
            named_type = Util.get_named_type_for_field_node(@supergraph.schema, parent_type, node)
            is_leaf_type = Util.is_leaf_type?(named_type)
            list_structure = Util.get_list_structure(node_type)

            raw_object[field_name] = if list_structure.any?
              resolve_list_scope(raw_object[field_name], list_structure, is_leaf_type, named_type, node.selections)
            elsif is_leaf_type
              raw_object[field_name]
            else
              resolve_object_scope(raw_object[field_name], named_type, node.selections)
            end
            return nil if raw_object[field_name].nil? && node_type.non_null?

          when GraphQL::Language::Nodes::InlineFragment
            next unless typename == node.type.name
            fragment_type = @supergraph.schema.types[node.type.name]
            result = resolve_object_scope(raw_object, fragment_type, node.selections, typename)
            return nil unless result

          when GraphQL::Language::Nodes::FragmentSpread
            next unless typename == node.name
            fragment = @document.fragment_definitions[node.name]
            fragment_type = @supergraph.schema.types[node.name]
            result = resolve_object_scope(raw_object, fragment_type, fragment.selections, typename)
            return nil unless result

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end

        raw_object
      end

      def resolve_list_scope(raw_list, list_structure, is_leaf_element, parent_type, selections)
        return nil unless raw_list

        current_structure = list_structure.shift
        next_structure = list_structure.first

        raw_list.map do |raw_list_element|
          case next_structure
          when "list", "non_null_list"
            result = resolve_list_scope(raw_list_element, list_structure.dup, is_leaf_element, parent_type, selections)
            return nil if result.nil? && current_structure == "non_null_list"
            result

          when "element", "non_null_element"
            result = if is_leaf_element
              raw_list_element
            else
              resolve_object_scope(raw_list_element, parent_type, selections)
            end

            return nil if result.nil? && current_structure == "non_null_element"
            result
          end
        end
      end
    end
  end
end
