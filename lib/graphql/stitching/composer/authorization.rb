# frozen_string_literal: true

module GraphQL::Stitching
  class Composer
    module Authorization
      private
      
      def merge_authorization_scopes(*scopes)
        merged_scopes = scopes.reduce([]) do |acc, or_scopes|
          expanded_scopes = []
          or_scopes.each do |and_scopes|
            if acc.any?
              acc.each do |acc_scopes|
                expanded_scopes << acc_scopes + and_scopes
              end
            else
              expanded_scopes << and_scopes.dup
            end
          end

          expanded_scopes
        end

        merged_scopes.each { _1.tap(&:sort!).tap(&:uniq!) }
        merged_scopes.tap(&:uniq!).tap(&:sort!)
      end
    end

    class SubgraphAuthorization
      include Authorization

      EMPTY_SCOPES = [EMPTY_ARRAY].freeze

      def initialize(schema)
        @schema = schema
      end

      def reverse_merge!(collector)
        @schema.types.each_value.with_object(collector) do |type, memo|
          next if type.introspection? || !type.kind.fields?

          type.fields.each_value do |field|
            field_scopes = scopes_for_field(type, field)
            if field_scopes.any?(&:any?)
              memo[type.graphql_name] ||= {}

              existing = memo[type.graphql_name][field.graphql_name]
              memo[type.graphql_name][field.graphql_name] = if existing
                merge_authorization_scopes(existing, field_scopes)
              else
                field_scopes
              end
            end
          end
        end
      end

      def collect
        reverse_merge!({})
      end
      
      private

      def scopes_for_field(parent_type, field)
        parent_type_scopes = scopes_from_directives(parent_type.directives)
        field_scopes = scopes_from_directives(field.directives)
        field_scopes = merge_authorization_scopes(parent_type_scopes, field_scopes)
        
        return_type = field.type.unwrap
        if return_type.kind.scalar? || return_type.kind.enum?
          return_type_scopes = scopes_from_directives(return_type.directives)
          field_scopes = merge_authorization_scopes(field_scopes, return_type_scopes)
        end

        each_corresponding_interface_field(parent_type, field.graphql_name) do |interface_type, interface_field|
          field_scopes = merge_authorization_scopes(field_scopes, scopes_from_directives(interface_type.directives))
          field_scopes = merge_authorization_scopes(field_scopes, scopes_from_directives(interface_field.directives))
        end

        field_scopes
      end

      def each_corresponding_interface_field(parent_type, field_name, &block)
        parent_type.interfaces.each do |interface_type|
          interface_field = interface_type.get_field(field_name)
          next if interface_field.nil?

          yield(interface_type, interface_field)
          each_corresponding_interface_field(interface_type, field_name, &block)
        end
      end

      def scopes_from_directives(directives)
        authorization = directives.find { _1.graphql_name == GraphQL::Stitching.authorization_directive }
        return EMPTY_SCOPES if authorization.nil?

        authorization.arguments.keyword_arguments[:scopes] || EMPTY_SCOPES
      end
    end
  end
end
