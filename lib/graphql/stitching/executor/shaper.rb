# frozen_string_literal: true
# typed: true

module GraphQL::Stitching
  class Executor
    class Shaper
      #: (Request request) -> void
      def initialize(request)
        @request = request #: Request
        @supergraph = request.supergraph #: Supergraph
        @root_type = nil #: CompositeType?
        @possible_type_names_by_type = nil #: Hash[TypeName, Array[TypeName]]?
      end

      #: (Data raw) -> Data?
      def perform!(raw)
        @root_type = @request.query.root_type_for_operation(@request.operation.operation_type)
        resolve_object_scope(raw, @root_type, @request.operation.selections, @root_type.graphql_name)
      end

      private

      #: (Data? raw_object, CompositeType parent_type, Array[SelectionNode] selections, ?TypeName? typename) -> Data?
      def resolve_object_scope(raw_object, parent_type, selections, typename = nil)
        return nil if raw_object.nil?

        typename ||= raw_object[TypeResolver::TYPENAME_EXPORT_NODE.alias]
        typename ||= parent_type.graphql_name unless parent_type.kind.abstract?

        raw_object.reject! { |key, _v| TypeResolver.export_key?(key) }

        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            field_name = node.alias || node.name
            raw_value = raw_object.delete(field_name)

            schema_field = @supergraph.memoized_schema_fields(parent_type.graphql_name).fetch(node.name)

            if schema_field.introspection?
              next if TypeResolver.export_key?(field_name)

              raw_object[field_name] = if node.name == TYPENAME && parent_type == @root_type
                @root_type.graphql_name
              else
                raw_value
              end
              next
            end

            node_type = schema_field.type
            named_type = node_type.unwrap

            raw_object[field_name] = if node_type.list?
              resolve_list_scope(raw_value, Util.unwrap_non_null(node_type), node.selections)
            elsif Util.is_leaf_type?(named_type)
              raw_value
            else
              resolve_object_scope(raw_value, named_type, node.selections)
            end

            return nil if node_type.non_null? && raw_object[field_name].nil?

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = node.type ? @supergraph.memoized_schema_types.fetch(node.type.name) : parent_type
            next unless typename_in_type?(typename, fragment_type)

            result = resolve_object_scope(raw_object, fragment_type, node.selections, typename)
            return nil if result.nil?

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions.fetch(node.name)
            fragment_type = @supergraph.memoized_schema_types.fetch(fragment.type.name)
            next unless typename_in_type?(typename, fragment_type)

            result = resolve_object_scope(raw_object, fragment_type, fragment.selections, typename)
            return nil if result.nil?

          else
            raise DocumentError.new("selection node type")
          end
        end

        raw_object
      end

      #: (Array[untyped]? raw_list, GraphQL::Schema::Wrapper current_node_type, Array[SelectionNode] selections) -> untyped
      def resolve_list_scope(raw_list, current_node_type, selections)
        return nil if raw_list.nil?

        next_node_type = Util.unwrap_non_null(current_node_type).of_type
        named_type = next_node_type.unwrap

        if Util.is_leaf_type?(named_type)
          return nil if next_node_type.non_null? && raw_list.include?(nil)

          return raw_list
        end

        resolved_list = raw_list.map! do |raw_list_element|
          result = if next_node_type.list?
            resolve_list_scope(raw_list_element, next_node_type, selections)
          else
            resolve_object_scope(raw_list_element, named_type, selections)
          end

          return nil if result.nil? && next_node_type.non_null?

          result
        end

        resolved_list
      end

      #: (TypeName? typename, CompositeType type) -> bool
      def typename_in_type?(typename, type)
        return true if type.graphql_name == typename
        return false unless typename && type.kind.abstract?

        possible_type_names(type).include?(typename)
      end

      #: (CompositeType type) -> Array[TypeName]
      def possible_type_names(type)
        (@possible_type_names_by_type ||= {})[type.graphql_name] ||= @request.query.possible_types(type).map(&:graphql_name)
      end
    end
  end
end
