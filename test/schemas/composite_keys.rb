# frozen_string_literal: true

module Schemas
  module CompositeKeys
    PAGES = [
      {
        id: '1',
        sku: 'p1',
        handle: 'mercury',
        scope: 'planet',
        title: 'Mercury, Planet',
        owner: { id: '1', type: 'Planet' },
      },
      {
        id: '2',
        sku: '80',
        handle: 'mercury',
        scope: 'element',
        title: 'Mercury, Element',
        owner: { id: '1', type: 'Element' },
      },
      {
        id: '3',
        sku: 'c1939',
        handle: 'mercury',
        scope: 'automobile',
        title: 'Mercury, Automobile',
        owner: { id: '1', type: 'Automobile' },
      },
    ].freeze

    class PagesById < GraphQL::Schema
      class Page < GraphQL::Schema::Object
        field :id, ID, null: false
        field :sku, ID, null: false
        field :title, String, null: false
        field :a, String, null: false

        def a
          "a#{object[:id]}"
        end
      end

      class Query < GraphQL::Schema::Object
        field :pages_by_id, [Page, null: true], null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "id"
          argument :ids, [ID], required: true
        end

        def pages_by_id(ids:)
          ids.map { |id| PAGES.find { _1[:id] == id } }
        end
      end

      query Query
    end

    class PagesBySku < GraphQL::Schema
      class Page < GraphQL::Schema::Object
        field :id, ID, null: false
        field :sku, ID, null: false
        field :handle, String, null: false
        field :scope, String, null: false
        field :b, String, null: false

        def b
          "b#{object[:id]}"
        end
      end

      class Query < GraphQL::Schema::Object
        field :pages_by_sku, [Page, null: true], null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "sku"
          argument :skus, [ID], required: true
        end

        def pages_by_sku(skus:)
          skus.map { |sku| PAGES.find { _1[:sku] == sku } }
        end
      end

      query Query
    end

    class PagesByScopedHandle < GraphQL::Schema
      class PageOwner < GraphQL::Schema::Object
        field :id, ID, null: false
        field :type, String, null: false
      end

      class Page < GraphQL::Schema::Object
        field :sku, ID, null: false
        field :handle, String, null: false
        field :scope, String, null: false
        field :owner, PageOwner, null: false
        field :c, String, null: false

        def c
          "c#{object[:id]}"
        end
      end

      class PageHandleKey < GraphQL::Schema::InputObject
        argument :handle, String, required: true
        argument :scope, String, required: true
      end

      class Query < GraphQL::Schema::Object
        field :pages_by_handle, [Page, null: true], null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "handle scope", arguments: "keys: { handle: $.handle, scope: $.scope }"
          argument :keys, [PageHandleKey], required: true
        end

        def pages_by_handle(keys:)
          keys.map do |key|
            PAGES.find { _1[:handle] == key.handle && _1[:scope] == key.scope }
          end
        end
      end

      query Query
    end

    class PagesByOwner < GraphQL::Schema
      class PageOwner < GraphQL::Schema::Object
        field :id, ID, null: false
        field :type, String, null: false
      end

      class Page < GraphQL::Schema::Object
        field :handle, String, null: false
        field :scope, String, null: false
        field :owner, PageOwner, null: false
        field :d, String, null: false

        def d
          "d#{object[:id]}"
        end
      end

      class PageOwnerKey < GraphQL::Schema::InputObject
        argument :id, ID, required: true
        argument :type, String, required: true
      end

      class Query < GraphQL::Schema::Object
        field :pages_by_owner, [Page, null: true], null: false do
          directive GraphQL::Stitching::Directives::Stitch, key: "owner { id type }", arguments: "keys: { id: $.owner.id, type: $.owner.type }"
          argument :keys, [PageOwnerKey], required: true
        end

        def pages_by_owner(keys:)
          keys.map do |key|
            PAGES.find { _1.dig(:owner, :id) == key.id && _1.dig(:owner, :type) == key.type }
          end
        end
      end

      query Query
    end

    class PagesByScopedHandleOrOwner < GraphQL::Schema
      class PageOwner < GraphQL::Schema::Object
        field :id, ID, null: false
        field :type, String, null: false
      end

      class Page < GraphQL::Schema::Object
        field :handle, String, null: false
        field :scope, String, null: false
        field :owner, PageOwner, null: false
        field :title, String, null: false
        field :e, String, null: false

        def e
          "e#{object[:id]}"
        end
      end

      class PageHandleKey < GraphQL::Schema::InputObject
        argument :handle, String, required: true
        argument :scope, String, required: true
      end

      class PageOwnerKey < GraphQL::Schema::InputObject
        argument :id, ID, required: true
        argument :type, String, required: true
      end

      class Query < GraphQL::Schema::Object
        field :pages_by_handle2, [Page, null: true], null: false do
          argument :keys, [PageHandleKey], required: true
        end

        def pages_by_handle2(keys:)
          keys.map do |key|
            PAGES.find { _1[:handle] == key.handle && _1[:scope] == key.scope }
          end
        end

        field :pages_by_owner2, [Page, null: true], null: false do
          argument :keys, [PageOwnerKey], required: true
        end

        def pages_by_owner2(keys:)
          keys.map do |key|
            PAGES.find { _1.dig(:owner, :id) == key.id && _1.dig(:owner, :type) == key.type }
          end
        end
      end

      query Query
    end
  end
end
