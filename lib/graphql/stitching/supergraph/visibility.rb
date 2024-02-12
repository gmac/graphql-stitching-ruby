# frozen_string_literal: true

module GraphQL::Stitching
  class Supergraph
    # Adds visibility controls to supergraph schema members.
    module Visibility
      class << self
        # @param schema [GraphQL::Schema] the schema to extend with visibility controls.
        def install(schema, enabled: false)
          defines_visibility = schema.directives.key?(GraphQL::Stitching.visibility_directive)

          if defines_visibility
            introspection_types = schema.introspection_system.types.values
            schema.types.each_value do |type|
              next if introspection_types.include?(type)

              type.extend(self)

              case type.kind.name
              when "ENUM"
                type.enum_values.each { _1.extend(self) }
              when "OBJECT", "INTERFACE"
                type.fields.each_value do |field|
                  field.extend(self)
                  field.arguments.each_value { _1.extend(self) }
                end
              when "INPUT_OBJECT"
                type.arguments.each_value { _1.extend(self) }
              end
            end
          else
            schema.use(GraphQL::Schema::AlwaysVisible)
          end

          schema
        end
      end

      def visible?(context)
        if request = context[:request]
          request.supergraph.visibility_guard.authorizes?(request, self)
        else
          true
        end
      end
    end
  end
end
