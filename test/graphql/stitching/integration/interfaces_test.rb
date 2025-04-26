# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/interfaces"

describe 'GraphQL::Stitching, merged interfaces' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Interfaces::Products,
      "bundles" => Schemas::Interfaces::Bundles,
    })
  end

  def test_queries_merged_interface_via_concrete
    query = %|
      query($ids: [ID!]!) {
        bundles(ids: $ids) {
          id
          name
          price
          products {
            id
            name
            price
          }
        }
      }
    |

    result = plan_and_execute(@supergraph, query, { "ids" => ["10"] })

    expected_result = {
      "bundles" => [
        {
          "id" => "10",
          "name" => "Apple Gear",
          "price" => 999.99,
          "products" => [
            {
              "id" => "1",
              "name" => "iPhone",
              "price" => 699.99
            },
            {
              "id" => "2",
              "name" => "Apple Watch",
              "price" => 399.99
            },
          ],
        },
      ],
    }

    assert_equal expected_result, result["data"]
  end

  def test_queries_merged_interface_via_full_interface
    query = %|
      query($ids: [ID!]!) {
        result: productsBuyables(ids: $ids) {
          id
          name
          price
        }
      }
    |

    result = plan_and_execute(@supergraph, query, { "ids" => ["1"] })

    expected_result = {
      "result" => [
        {
          "id" => "1",
          "name" => "iPhone",
          "price" => 699.99,
        },
      ],
    }

    assert_equal expected_result, result["data"]
  end

  def test_queries_merged_interface_via_partial_interface
    query = %|
      query($ids: [ID!]!) {
        result: bundlesBuyables(ids: $ids) {
          id
          name
          price
          ... on Bundle {
            products {
              id
              name
              price
            }
          }
        }
      }
    |

    result = plan_and_execute(@supergraph, query, { "ids" => ["10"] })

    expected_result = {
      "result" => [
        {
          "id" => "10",
          "name" => "Apple Gear",
          "price" => 999.99,
          "products" => [
            {
              "id" => "1",
              "name" => "iPhone",
              "price" => 699.99
            },
            {
              "id" => "2",
              "name" => "Apple Watch",
              "price" => 399.99
            },
          ],
        },
      ],
    }

    assert_equal expected_result, result["data"]
  end

  def test_queries_merged_split_interface
    query1 = %|
      query($ids: [ID!]!) {
        result: productsSplit(ids: $ids) {
          id
          name
          price
        }
      }
    |

    query2 = %|
      query($ids: [ID!]!) {
        result: bundlesSplit(ids: $ids) {
          id
          name
          price
        }
      }
    |

    result1 = plan_and_execute(@supergraph, query1, { "ids" => ["100", "200"] })
    result2 = plan_and_execute(@supergraph, query2, { "ids" => ["100", "200"] })

    expected_result = {
      "data" => {
        "result" => [
          {
            "id" => "100",
            "name" => "Widget",
            "price" => 10.99,
          },
          {
            "id" => "200",
            "name" => "Sprocket",
            "price" => 9.99,
          },
        ],
      },
    }

    assert_equal expected_result, result1.to_h
    assert_equal expected_result, result2.to_h
  end

  def test_merges_within_interface_fragments
    query = %|
      query($ids: [ID!]!) {
        result: nodes(ids: $ids) {
          id
          ...on Buyable { name price }
          ...on Split { name price }
          __typename
        }
      }
    |

    result = plan_and_execute(@supergraph, query, { "ids" => ["1", "100"] })

    expected_result = {
      "data" => {
        "result"=> [{
          "id" => "1",
          "name" => "iPhone",
          "price" => 699.99,
          "__typename" => "Product",
        }, {
          "id" => "100",
          "name" => "Widget",
          "price" => 10.99,
          "__typename" => "Gizmo",
        }],
      },
    }

    assert_equal expected_result, result.to_h
  end
end
