module Shopify
  # Read-only view of the products this app seeded (tagged "seeded"),
  # read live from Shopify so the pages always match the store.
  class ProductCatalog
    SEEDED_TAG = "seeded".freeze

    # Fields shown in product lists (Products page, dashboard thumbnails).
    LIST_FIELDS = <<~GQL.freeze
      id title vendor productType status tags
      variantsCount { count }
      featuredMedia { preview { image { url(transform: { maxWidth: 120, maxHeight: 120 }) } } }
      metafield(namespace: "#{ProductImporter::NAMESPACE}", key: "#{ProductImporter::KEY}") { value }
    GQL

    LIST_QUERY = <<~GQL.freeze
      query SeededProducts($query: String!) {
        products(first: 50, query: $query, sortKey: TITLE) { nodes { #{LIST_FIELDS} } }
      }
    GQL

    PRODUCT_QUERY = <<~GQL.freeze
      query SeededProduct($id: ID!) {
        product(id: $id) {
          id title descriptionHtml vendor productType status tags createdAt updatedAt
          category { fullName }
          featuredMedia { preview { image { url(transform: { maxWidth: 600, maxHeight: 600 }) altText } } }
          metafield(namespace: "#{ProductImporter::NAMESPACE}", key: "#{ProductImporter::KEY}") { value }
          variants(first: 10) {
            nodes {
              id title price compareAtPrice sku
              selectedOptions { name value }
              barcodes(first: 1) { nodes { value } }
              inventoryItem { measurement { weight { value unit } } }
            }
          }
        }
      }
    GQL

    # Lookup by ID, not search: Shopify's search index lags a few seconds behind,
    # so products created moments ago are not yet returned by products(query:).
    NODES_QUERY = <<~GQL.freeze
      query SeededProductsById($ids: [ID!]!) {
        nodes(ids: $ids) { ... on Product { #{LIST_FIELDS} } }
      }
    GQL

    def initialize(client: GraphqlClient.new)
      @client = client
    end

    # Array of seeded product hashes, sorted by title. `also_ids` (e.g. the last seed
    # run's products) are looked up by ID too, so products created moments ago appear
    # even before Shopify's search index includes them.
    def all(also_ids: [])
      found = @client.query(LIST_QUERY, query: "tag:#{SEEDED_TAG}").dig("products", "nodes")
      missing = also_ids - found.map { |p| p["id"] }
      extra = find_by_ids(missing).values.select { |p| Array(p["tags"]).include?(SEEDED_TAG) }
      (found + extra).sort_by { |p| p["title"].to_s.downcase }
    end

    # Products that still exist, by ID: { product_gid => product hash }. Deleted ones are
    # absent. Immediate (no search-index delay), so it is safe right after a seed.
    def find_by_ids(gids)
      return {} if gids.empty?

      Array(@client.query(NODES_QUERY, ids: gids)["nodes"]).compact.index_by { |p| p["id"] }
    end

    # Product hash, or nil when it does not exist or was not seeded by this app.
    def find(id)
      product = @client.query(PRODUCT_QUERY, id: "gid://shopify/Product/#{id.to_i}")["product"]
      product if product && Array(product["tags"]).include?(SEEDED_TAG)
    end
  end
end
