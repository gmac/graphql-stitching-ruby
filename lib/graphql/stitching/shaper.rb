# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Shaper
      def initialize(schema:, request:)
        @schema = schema
        @request = request
      end

      def perform!(raw)
        root_type = @schema.public_send(@request.operation.operation_type)
        resolve_object_scope(raw, root_type, @request.operation.selections)
      end

      private

      def resolve_object_scope(raw_object, parent_type, selections, typename = nil)
        return nil if raw_object.nil?

        typename ||= raw_object["_STITCH_typename"]
        raw_object.reject! { |k, _v| k.start_with?("_STITCH_") }

        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            next if introspection_field?(parent_type, node)

            field_name = node.alias || node.name
            node_type = parent_type.fields[node.name].type
            named_type = node_type.unwrap

            raw_object[field_name] = if node_type.list?
              resolve_list_scope(raw_object[field_name], Util.unwrap_non_null(node_type), node.selections)
            elsif Util.is_leaf_type?(named_type)
              raw_object[field_name]
            else
              resolve_object_scope(raw_object[field_name], named_type, node.selections)
            end

            return nil if raw_object[field_name].nil? && node_type.non_null?

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = @schema.types[node.type.name]
            next unless typename_in_type?(typename, fragment_type)

            result = resolve_object_scope(raw_object, fragment_type, node.selections, typename)
            return nil if result.nil?

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions[node.name]
            fragment_type = @schema.types[fragment.type.name]
            next unless typename_in_type?(typename, fragment_type)

            result = resolve_object_scope(raw_object, fragment_type, fragment.selections, typename)
            return nil if result.nil?

          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end

        raw_object
      end

      def resolve_list_scope(raw_list, current_node_type, selections)
        return nil if raw_list.nil?

        next_node_type = Util.unwrap_non_null(current_node_type).of_type
        named_type = next_node_type.unwrap
        contains_null = false

        resolved_list = raw_list.map! do |raw_list_element|
          result = if next_node_type.list?
            resolve_list_scope(raw_list_element, next_node_type, selections)
          elsif Util.is_leaf_type?(named_type)
            raw_list_element
          else
            resolve_object_scope(raw_list_element, named_type, selections)
          end

          if result.nil?
            contains_null = true
            return nil if current_node_type.non_null?
          end

          result
        end

        return nil if contains_null && next_node_type.non_null?

        resolved_list
      end

      def introspection_field?(parent_type, node)
        return false unless node.name.start_with?("__")

        case node.name
        when "__typename"
          true
        when "__schema", "__type"
          parent_type == @schema.query
        else
          false
        end
      end

      def typename_in_type?(typename, type)
        return true if type.graphql_name == typename
        type.kind.abstract? && @schema.possible_types(type).any? { _1.graphql_name == typename }
      end
    end
  end
end
