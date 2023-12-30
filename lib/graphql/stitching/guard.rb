# frozen_string_literal: true

module GraphQL
  module Stitching
    class Guard
      def initialize
        @policies = nil
      end

      def authorizes?(request, member)
        access_directive = member.directives.find { _1.graphql_name == "access" }
        return true unless access_directive

        access = true
        kwargs = access_directive.arguments.keyword_arguments

        access_scopes = kwargs[:scopes]
        if access_scopes
          claims = request.claims || GraphQL::Stitching::EMPTY_ARRAY
          access &&= access_scopes.any? do |scopes|
            scopes.all? { |scope| claims.include?(scope) }
          end
        end

        access_policy = kwargs[:policy]
        if access_policy
          fn = @policies ? @policies[policy_name] : nil
          access &&= (fn ? fn.call(request, member) : false)
        end

        access
      end

      def policy(name, &block)
        @policies ||= {}
        @policies[name] = block
      end
    end
  end
end
