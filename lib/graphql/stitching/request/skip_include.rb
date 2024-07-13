# frozen_string_literal: true

module GraphQL::Stitching
  class Request
    # Faster implementation of an AST visitor for prerendering
    # @skip and @include conditional directives into a document.
    # This avoids unnecessary planning steps, and prepares result shaping.
    # @api private
    class SkipInclude
      class << self
        def render(document, variables)
          changed = false
          definitions = document.definitions.map do |original_definition|
            definition = render_node(original_definition, variables)
            changed ||= definition.object_id != original_definition.object_id
            definition
          end

          return document unless changed

          document = document.merge(definitions: definitions)
          yield(document) if block_given?
          document
        end

        private

        def render_node(parent_node, variables)
          changed = false
          filtered_selections = parent_node.selections.filter_map do |original_node|
            node = prune_node(original_node, variables)
            if node.nil?
              changed = true
              next nil
            end

            node = render_node(node, variables) if node.selections.any?
            changed ||= node.object_id != original_node.object_id
            node
          end

          if filtered_selections.none?
            filtered_selections << Resolver::TYPENAME_EXPORT_NODE
          end

          if changed
            parent_node.merge(selections: filtered_selections)
          else
            parent_node
          end
        end

        def prune_node(node, variables)
          return node unless node.directives.any?

          delete_node = false
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
