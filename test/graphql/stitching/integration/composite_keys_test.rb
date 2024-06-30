# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/composite_keys"

describe 'GraphQL::Stitching, composite keys' do
  def test_queries_through_multiple_composite_keys_from_outer_edge
    @supergraph = compose_definitions({
      "a" => Schemas::CompositeKeys::PagesById,
      "b" => Schemas::CompositeKeys::PagesBySku,
      "c" => Schemas::CompositeKeys::PagesByScopedHandle,
      "d" => Schemas::CompositeKeys::PagesByOwner,
    })

    # id > sku > handle scope > owner { id type }
    query = %|{ pagesById(ids: ["1", "2"]) { id a b c d title } }|
    result = plan_and_execute(@supergraph, query)
    expected = {
      "pagesById" => [
        { "id" => "1", "a" => "a1", "b" => "b1", "c" => "c1", "d" => "d1", "title" => "Mercury, Planet" },
        { "id" => "2", "a" => "a2", "b" => "b2", "c" => "c2", "d" => "d2", "title" => "Mercury, Element" },
      ],
    }

    assert_equal expected, result["data"]
  end

  def test_queries_through_multiple_composite_keys_from_center
    @supergraph = compose_definitions({
      "a" => Schemas::CompositeKeys::PagesById,
      "b" => Schemas::CompositeKeys::PagesBySku,
      "c" => Schemas::CompositeKeys::PagesByScopedHandle,
      "d" => Schemas::CompositeKeys::PagesByOwner,
    })

    # id < sku < handle scope > owner { id type }
    query = %|{
      pagesByHandle(keys: [
        { handle: "mercury", scope: "planet" },
        { handle: "mercury", scope: "automobile" },
      ]) { id a b c d title }
    }|

    result = plan_and_execute(@supergraph, query)
    expected = {
      "pagesByHandle" => [
        { "id" => "1", "a" => "a1", "b" => "b1", "c" => "c1", "d" => "d1", "title" => "Mercury, Planet" },
        { "id" => "3", "a" => "a3", "b" => "b3", "c" => "c3", "d" => "d3", "title" => "Mercury, Automobile" },
      ],
    }

    assert_equal expected, result["data"]
  end

  def test_queries_through_single_composite_key
    @supergraph = compose_definitions({
      "c" => Schemas::CompositeKeys::PagesByScopedHandle,
      "e" => {
        schema: Schemas::CompositeKeys::PagesByScopedHandleOrOwner,
        stitch: [{
          field_name: "pagesByHandle2",
          key: "handle scope",
          arguments: "keys: { handle: $.handle, scope: $.scope }",
        }],
      }
    })

    # "handle scope" > "handle scope"
    query = %|{
      pagesByHandle(keys: [
        { handle: "mercury", scope: "planet" },
        { handle: "mercury", scope: "automobile" },
      ]) { c e title }
    }|

    result = plan_and_execute(@supergraph, query)
    expected = {
      "pagesByHandle" => [
        { "c" => "c1", "e" => "e1", "title" => "Mercury, Planet" },
        { "c" => "c3", "e" => "e3", "title" => "Mercury, Automobile" },
      ],
    }

    assert_equal expected, result["data"]
  end

  def test_queries_through_single_composite_key_with_nesting
    @supergraph = compose_definitions({
      "d" => Schemas::CompositeKeys::PagesByOwner,
      "e" => {
        schema: Schemas::CompositeKeys::PagesByScopedHandleOrOwner,
        stitch: [{
          field_name: "pagesByOwner2",
          key: "owner { id type }",
          arguments: "keys: { id: $.owner.id, type: $.owner.type }",
        }],
      }
    })

    # "owner { id type }" > "owner { id type }"
    query = %|{
      pagesByOwner(keys: [
        { id: "1", type: "Planet" },
        { id: "1", type: "Element" },
      ]) { d e title }
    }|

    result = plan_and_execute(@supergraph, query)
    expected = {
      "pagesByOwner" => [
        { "d" => "d1", "e" => "e1", "title" => "Mercury, Planet" },
        { "d" => "d2", "e" => "e2", "title" => "Mercury, Element" },
      ],
    }

    assert_equal expected, result["data"]
  end
end
