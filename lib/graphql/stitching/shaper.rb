# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Shaper
      def initialize(schema:, document:)
        @schema = schema
        @document = document
        @errors = []
      end

      def perform!(raw)
        raw["data"] = resolve_object_scope(raw["data"], @schema.query, @document.operation.selections)
        raw
      end

      private

      def resolve_object_scope(raw_object, parent_type, selections, typename = nil)
        return nil if raw_object.nil?

        typename ||= raw_object["_STITCH_typename"]
        raw_object.reject! { |k, _v| k.start_with?("_STITCH_") }

        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            next if node.name == "__typename"

            field_name = node.alias || node.name
            node_type = parent_type.fields[node.name].type
            named_type = Util.get_named_type_for_field_node(@schema, parent_type, node)
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
            fragment_type = @schema.types[node.type.name]
            result = resolve_object_scope(raw_object, fragment_type, node.selections, typename)
            return nil if result.nil?

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @document.fragment_definitions[node.name]
            fragment_type = @schema.types[fragment.type.name]
            next unless typename == fragment_type.graphql_name

            result = resolve_object_scope(raw_object, fragment_type, fragment.selections, typename)
            return nil if result.nil?

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end

        raw_object
      end

      def resolve_list_scope(raw_list, list_structure, is_leaf_element, parent_type, selections)
        return nil if raw_list.nil?

        current_structure = list_structure.shift
        next_structure = list_structure.first

        resolved_list = raw_list.map do |raw_list_element|
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

        return nil if next_structure.start_with?("non_null") && resolved_list.any?(&:nil?)

        resolved_list
      end
    end
  end
end
