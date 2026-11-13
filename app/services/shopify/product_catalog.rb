module Shopify
  # Read-only view of the products this app seeded (tagged "seeded"),
  # read live from Shopify so the pages always match the store.
  class ProductCatalog
    SEEDED_TAG = "seeded".freeze

    LIST_QUERY = <<~GQL.freeze
      query SeededProducts($query: String!) {
        products(first: 50, query: $query, sortKey: TITLE) {
          nodes {
            id title vendor productType status
            variantsCount { count }
            featuredMedia { preview { image { url(transform: { maxWidth: 120, maxHeight: 120 }) } } }
            metafield(namespace: "#{ProductImporter::NAMESPACE}", key: "#{ProductImporter::KEY}") { value }
          }
        }
      }
    GQL

    PRODUCT_QUERY = <<~GQL.freeze
      query SeededProduct($id: ID!) {
        product(id: $id) {
          id title descriptionHtml vendor productType status tags createdAt updatedAt
          featuredMedia { preview { image { url(transform: { maxWidth: 600, maxHeight: 600 }) altText } } }
          metafield(namespace: "#{ProductImporter::NAMESPACE}", key: "#{ProductImporter::KEY}") { value }
          variants(first: 10) { nodes { id title price sku selectedOptions { name value } } }
        }
      }
    GQL

    def initialize(client: GraphqlClient.new)
      @client = client
    end

    # Array of product hashes.
    def all
      @client.query(LIST_QUERY, query: "tag:#{SEEDED_TAG}").dig("products", "nodes")
    end

    # Product hash, or nil when it does not exist or was not seeded by this app.
    def find(id)
      product = @client.query(PRODUCT_QUERY, id: "gid://shopify/Product/#{id.to_i}")["product"]
      product if product && Array(product["tags"]).include?(SEEDED_TAG)
    end
  end
end
