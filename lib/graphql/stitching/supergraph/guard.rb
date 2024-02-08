# frozen_string_literal: true

module GraphQL::Stitching
  class Supergraph
    class Guard
      def initialize(scope:)
        @scope = scope
        @policies = nil
      end

      def authorizes?(request, member)
        auth_directive = member.directives.find { _1.graphql_name == @scope }
        return true unless auth_directive

        authorized = true
        kwargs = auth_directive.arguments.keyword_arguments

        auth_scopes = kwargs[:scopes]
        if auth_scopes
          claims = if @scope == GraphQL::Stitching.visibility_directive
            request.visibility_claims
          end

          claims ||= GraphQL::Stitching::EMPTY_ARRAY
          authorized &&= fulfills?(auth_scopes) { |scope| claims.include?(scope) }
        end

        auth_policies = kwargs[:policy]
        if auth_policies
          authorized &&= fulfills?(auth_policies) do |scope|
            if fn = @policies[scope]
              fn.call(request, member)
            else
              false
            end
          end
        end

        authorized
      end

      def policy(name, &block)
        @policies ||= {}
        @policies[name] = block
      end

      private

      def fulfills?(or_scopes)
        or_scopes.any? do |and_scopes|
          and_scopes.all? { |scope| yield(scope) }
        end
      end
    end
  end
end
