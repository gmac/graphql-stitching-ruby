# typed: false
# frozen_string_literal: true

module GraphQL
  module Stitching
    class Shaper
      def perform(schema, document, raw_result)
        # - Traverse the document (same basic steps as Planner.extract_locale_selections)
        # - Recursively reduce result nodes based on schema rules...
        # - For each scope:
        #   - Eliminate extra attributes (stitching artifacts)
        #   - Add missing fields requested in the document, value is null
        # - Not-null violations invalidate the scope, and invalidations bubble

        result = traverse({}, raw_result[:data], document.operation.selections, schema.query, [])

        {data: result}
      end

      private

      def traverse(result, raw, selections, parent_type, path)
        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            node_type = field_type(node, parent_type)
            node_identifier = (node.alias || node.name).to_sym

            raw_value = raw[node_identifier]

            result[node_identifier] = if Util.is_leaf_type?(node_type)
              raw_value
            elsif raw_value.is_a? Array
              raw_value.map do |raw_item|
                traverse(raw_item.class.new, raw_item, node.selections, node_type, path)
              end
            else
              node_path = [*path, node_identifier]

              traverse(raw_value.class.new, raw_value, node.selections, node_type, node_path)
            end

          # TODO when GraphQL::Language::Nodes::InlineFragment

          # TODO when GraphQL::Language::Nodes::FragmentSpread
          else
            raise "Unexpected node of type #{node.class.name} in selection set."
          end
        end

        return result
      end

      def field_type(node, parent_type)
        if node.name == "__schema" && parent_type == @supergraph.schema.query
          @supergraph.schema.types["__Schema"] # type mapped to phantom introspection field
        else
          Util.get_named_type(parent_type.fields[node.name].type)
        end
      end
    end
  end
end
