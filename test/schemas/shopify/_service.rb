class ShopifyService
  class << self
    def store
      @store ||= {}
    end

    def add_data_set(store_name, records)
      store[store_name] = records.each_with_object({}) { |i, o| o[i['id']] = i }
    end

    def products_by_ids(ids)
      table = @store['products']
      ids.map { |id| table[id] }
    end

    def variants_by_ids(ids)
      table = @store['variants']
      ids.map { |id| table[id] }
    end

    def collections_by_ids(ids)
      table = @store['collections']
      ids.map { |id| table[id] }
    end

    def variants_for_product(product_id)
      @store['variants'].values.each_with_object([]) do |row, memo|
        next unless row['product_id'] == product_id
        memo << row
      end
    end

    def collections_for_product(product_id)
      table = @store['collections']
      @store['collects'].values.each_with_object([]) do |row, memo|
        next unless row['product_id'] == product_id
        memo << table[row['collection_id']]
      end
    end

    def products_for_collection(collection_id)
      table = @store['products']
      @store['collects'].values.each_with_object([]) do |row, memo|
        next unless row['collection_id'] == collection_id
        memo << table[row['product_id']]
      end
    end
  end
end

ShopifyService.add_data_set('products', [
  { 'id' => 'Product/1', 'title' => 'Mercury' },
  { 'id' => 'Product/2', 'title' => 'Venus' },
  { 'id' => 'Product/3', 'title' => 'Earth' },
  { 'id' => 'Product/4', 'title' => 'Mars' },
  { 'id' => 'Product/5', 'title' => 'Jupiter' },
  { 'id' => 'Product/6', 'title' => 'Saturn' },
  { 'id' => 'Product/7', 'title' => 'Neptune' },
  { 'id' => 'Product/8', 'title' => 'Uranus' },
])

ShopifyService.add_data_set('variants', [
  { 'id' => 'Variant/1', 'title' => 'a', 'price' => 23, 'product_id' => 'Product/1' },
  { 'id' => 'Variant/2', 'title' => 'b', 'price' => 12, 'product_id' => 'Product/1' },
  { 'id' => 'Variant/3', 'title' => 'c', 'price' => 4, 'product_id' => 'Product/2' },
  { 'id' => 'Variant/4', 'title' => 'd', 'price' => 23, 'product_id' => 'Product/2' },
  { 'id' => 'Variant/5', 'title' => 'e', 'price' => 77, 'product_id' => 'Product/3' },
  { 'id' => 'Variant/6', 'title' => 'f', 'price' => 9, 'product_id' => 'Product/3' },
  { 'id' => 'Variant/7', 'title' => 'g', 'price' => 106, 'product_id' => 'Product/4' },
  { 'id' => 'Variant/8', 'title' => 'h', 'price' => 47, 'product_id' => 'Product/4' },
  { 'id' => 'Variant/9', 'title' => 'i', 'price' => 39, 'product_id' => 'Product/5' },
  { 'id' => 'Variant/10', 'title' => 'j', 'price' => 82, 'product_id' => 'Product/5' },
  { 'id' => 'Variant/11', 'title' => 'k', 'price' => 26, 'product_id' => 'Product/6' },
  { 'id' => 'Variant/12', 'title' => 'l', 'price' => 451, 'product_id' => 'Product/6' },
  { 'id' => 'Variant/13', 'title' => 'm', 'price' => 92, 'product_id' => 'Product/7' },
  { 'id' => 'Variant/14', 'title' => 'n', 'price' => 11, 'product_id' => 'Product/7' },
  { 'id' => 'Variant/15', 'title' => 'o', 'price' => 1, 'product_id' => 'Product/8' },
  { 'id' => 'Variant/16', 'title' => 'p', 'price' => 22, 'product_id' => 'Product/8' },
])

ShopifyService.add_data_set('collections', [
  { 'id' => 'Collection/1', 'title' => 'Featured' },
  { 'id' => 'Collection/2', 'title' => 'Up and Coming' },
  { 'id' => 'Collection/3', 'title' => 'Seasonal' },
])

ShopifyService.add_data_set('collects', [
  { 'id' => '1', 'product_id' => 'Product/1', 'collection_id' => 'Collection/1' },
  { 'id' => '2', 'product_id' => 'Product/1', 'collection_id' => 'Collection/2' },
  { 'id' => '3', 'product_id' => 'Product/2', 'collection_id' => 'Collection/3' },
  { 'id' => '4', 'product_id' => 'Product/2', 'collection_id' => 'Collection/1' },
  { 'id' => '5', 'product_id' => 'Product/3', 'collection_id' => 'Collection/1' },
  { 'id' => '6', 'product_id' => 'Product/3', 'collection_id' => 'Collection/2' },
  { 'id' => '7', 'product_id' => 'Product/4', 'collection_id' => 'Collection/3' },
  { 'id' => '8', 'product_id' => 'Product/4', 'collection_id' => 'Collection/2' },
  { 'id' => '9', 'product_id' => 'Product/5', 'collection_id' => 'Collection/1' },
  { 'id' => '10', 'product_id' => 'Product/5', 'collection_id' => 'Collection/3' },
  { 'id' => '11', 'product_id' => 'Product/6', 'collection_id' => 'Collection/1' },
  { 'id' => '12', 'product_id' => 'Product/6', 'collection_id' => 'Collection/2' },
  { 'id' => '13', 'product_id' => 'Product/7', 'collection_id' => 'Collection/3' },
  { 'id' => '14', 'product_id' => 'Product/7', 'collection_id' => 'Collection/1' },
  { 'id' => '15', 'product_id' => 'Product/8', 'collection_id' => 'Collection/1' },
  { 'id' => '16', 'product_id' => 'Product/8', 'collection_id' => 'Collection/3' },
])
