# frozen_string_literal: true

module GraphQL
  module Stitching
    # Defines a root resolver query that provides direct access to an entity type.
    Resolver = Struct.new(
      # location name providing the resolver root query.
      :location,

      # merged type name to fulfill through this resolver.
      :type_name,

      # key to select from prior locations
      :key,

      # root field to query for this merged type
      :field,

      # specifies the name of the argument used to send the key.
      :arg,

      # specifies if the resolver is a list endpoint (preferred)
      :list,

      # specifies if keys should be sent to the servive as primitive representations.
      :representations,
      keyword_init: true
    ) do
      alias_method :list?, :list
      alias_method :representations?, :representations

      def as_json
        {
          location: location,
          type_name: type_name,
          key: key,
          field: field,
          arg: arg,
          list: list,
          representations: representations,
        }.tap(&:compact!)
      end
    end
  end
end
