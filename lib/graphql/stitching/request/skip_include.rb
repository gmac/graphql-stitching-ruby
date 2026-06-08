# frozen_string_literal: true
# typed: true

module GraphQL::Stitching
  class Request
    class SkipInclude
      class << self
        #: (DocumentNode document, Variables variables) { (DocumentNode) -> void } -> DocumentNode
        def render(document, variables, &block)
          changed = false #: bool
          definitions = document.definitions.map do |original_definition|
            definition = render_node(original_definition, variables)
            changed ||= definition.object_id != original_definition.object_id
            definition
          end

          return document unless changed

          document = document.merge(definitions: definitions)
          block.call(document) if block
          document
        end

        private

        #: ((SelectionSetNode) parent_node, Variables variables) -> SelectionSetNode
        def render_node(parent_node, variables)
          changed = false #: bool
          filtered_selections = parent_node.selections.filter_map do |original_node|
            node = prune_node(original_node, variables)
            if node.nil?
              changed = true
              next nil
            end

            node = render_node(node, variables) unless node.selections.empty?
            changed ||= node.object_id != original_node.object_id
            node
          end

          if filtered_selections.none?
            filtered_selections << TypeResolver::TYPENAME_EXPORT_NODE
          end

          if changed
            parent_node.merge(selections: filtered_selections)
          else
            parent_node
          end
        end

        #: (SelectionSetNode node, Variables variables) -> SelectionSetNode?
        def prune_node(node, variables)
          return node if node.directives.empty?

          delete_node = false #: bool
          filtered_directives = node.directives.reject do |directive|
            if directive.name == "skip"
              delete_node = assess_condition(directive.arguments.first, variables)
              true
            elsif directive.name == "include"
              delete_node = !assess_condition(directive.arguments.first, variables)
              true
            end
          end

          if delete_node
            nil
          elsif filtered_directives.length != node.directives.length
            node.merge(directives: filtered_directives)
          else
            node
          end
        end

        #: (untyped arg, Variables variables) -> bool
        def assess_condition(arg, variables)
          if arg.value.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
            variables[arg.value.name] || variables[arg.value.name.to_sym]
          else
            arg.value
          end
        end
      end
    end
  end
end
