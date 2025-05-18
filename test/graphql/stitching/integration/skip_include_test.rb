# frozen_string_literal: true

require "test_helper"
require_relative "../../../schemas/example"

describe 'GraphQL::Stitching, skip/include' do
  def setup
    @supergraph = compose_definitions({
      "products" => Schemas::Example::Products,
      "storefronts" => Schemas::Example::Storefronts,
      "manufacturers" => Schemas::Example::Manufacturers,
    })
  end

  def test_skips_partial_object_fields
    query = %|
      query($id: ID!) {
        storefront(id: $id) {
          products {
            upc
            manufacturer @skip(if: true) {
              name
            }
          }
        }
      }
    |

    result = plan_and_execute(@supergraph, query, { "id" => "1" })
    expected = {
      "storefront" => {
        "products" => [
          { "upc" => "1" },
          { "upc" => "2" },
        ],
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_skips_all_object_fields
    query = %|
      query($id: ID!) {
        storefront(id: $id) {
          products {
            manufacturer @skip(if: true) {
              name
            }
          }
        }
      }
    |

    result = plan_and_execute(@supergraph, query, { "id" => "1" })
    expected = {
      "storefront" => {
        "products" => [
          {},
          {},
        ],
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_skips_partial_root_fields
    query = %|{
      product(upc: "1") {
        upc
      }
      storefront(id: "1") @skip(if: true) {
        id
      }
    }|

    result = plan_and_execute(@supergraph, query)
    expected = {
      "product" => { "upc" => "1" }
    }

    assert_equal expected, result.dig("data")
  end

  def test_skips_all_root_fields
    query = %|
      query($id: ID!) {
        storefront(id: $id) @skip(if: true) {
          id
        }
      }
    |

    result = plan_and_execute(@supergraph, query, { "id" => "1" })
    expected = {}

    assert_equal expected, result.dig("data")
  end
end
