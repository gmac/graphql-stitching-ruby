# frozen_string_literal: true

module GraphQL
  module Stitching
    # Defines a root resolver query that provides direct access to an entity type.
    Resolver = Struct.new(
      # location name providing the resolver query.
      :location,

      # name of merged type fulfilled through this resolver.
      :type_name,

      # a key field to select from prior locations, sent as resolver argument.
      :key,

      # name of the root field to query.
      :field,

      # specifies when the resolver is a list query.
      :list,

      # name of the root field argument used to send the key.
      :arg,

      # type name of the root field argument used to send the key.
      :arg_type_name,

      # specifies that keys should be sent as JSON representations with __typename and key.
      :representations,
      keyword_init: true
    ) do
      alias_method :list?, :list
      alias_method :representations?, :representations

      def version
        @version ||= Digest::SHA2.hexdigest(as_json.to_json)
      end

      def as_json
        {
          location: location,
          type_name: type_name,
          key: key,
          field: field,
          list: list,
          arg: arg,
          arg_type_name: arg_type_name,
          representations: representations,
        }.tap(&:compact!)
      end
    end
  end
end
