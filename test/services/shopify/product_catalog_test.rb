require "test_helper"

class Shopify::ProductCatalogTest < ActiveSupport::TestCase
  setup do
    create_setting
    stub_token("tok-1")
    stub_dummyjson
    @shopify = FakeShopify.new
    @shopify.install(self)
    Shopify::ProductImporter.call
    @catalog = Shopify::ProductCatalog.new
  end

  test "lists seeded products filtered by the seeded tag" do
    products = @catalog.all

    assert_equal 3, products.size
    assert_requested(:post, ShopifyTestHelpers::GRAPHQL_URL) do |req|
      body = JSON.parse(req.body)
      body["query"].include?("SeededProducts") && body["variables"] == { "query" => "tag:seeded" }
    end
  end

  test "finds one product with its two variants" do
    id = @shopify.products["1"]["id"].split("/").last

    product = @catalog.find(id)

    assert_equal "Essence Mascara Lash Princess", product["title"]
    variants = product.dig("variants", "nodes")
    assert_equal %w[Standard Premium], variants.map { |v| v["title"] }
    assert_equal %w[9.99 12.49], variants.map { |v| v["price"] }
  end

  test "returns nil for an unknown product" do
    assert_nil @catalog.find("999999")
  end

  test "returns nil for a product not seeded by this app" do
    @shopify.products["1"]["tags"] = [ "other" ]
    id = @shopify.products["1"]["id"].split("/").last

    assert_nil @catalog.find(id)
  end
end
