require "test_helper"

class Shopify::ProductImporterTest < ActiveSupport::TestCase
  setup do
    create_setting
    stub_token("tok-1")
    stub_dummyjson
    @shopify = FakeShopify.new
    @shopify.install(self)
  end

  test "first run creates three products, each with two variants and an image" do
    run = Shopify::ProductImporter.call

    assert_equal "completed", run.status
    assert_equal [ 3, 0, 0, 0 ], [ run.created_count, run.updated_count, run.skipped_count, run.failed_count ]
    assert_equal %w[1 2 3], @shopify.products.keys.sort
    @shopify.products.each_value do |product|
      assert_equal 2, product.dig("variantsCount", "count")
      assert_equal 1, product.dig("media", "nodes").size
    end
  end

  test "sends the expected productSet input" do
    Shopify::ProductImporter.call

    assert_requested(:post, ShopifyTestHelpers::GRAPHQL_URL) do |req|
      body = JSON.parse(req.body)
      next false unless body["query"].include?("productSet")

      vars = body["variables"]
      input = vars["input"]
      vars["identifier"] == { "customId" => { "namespace" => "seeder", "key" => "dummyjson_id", "value" => "1" } } &&
        input["title"] == "Essence Mascara Lash Princess" &&
        input["variants"].map { |v| v["price"] } == %w[9.99 12.49] &&
        input["variants"].map { |v| v["sku"] } == %w[BEA-ESS-ESS-001-STD BEA-ESS-ESS-001-PRM] &&
        input["files"].first["originalSource"].end_with?("thumbnail.webp") &&
        input["tags"] == %w[dummyjson seeded beauty mascara] &&
        input["productType"] == "Beauty" &&
        input["category"] == "gid://shopify/TaxonomyCategory/hb" &&
        input["variants"].map { |v| v["compareAtPrice"] } == %w[11.16 13.95] &&
        input["variants"].map { |v| v["barcodes"] } == [ [ { "value" => "5784719087687" } ], nil ] &&
        input["variants"].all? { |v| v.dig("inventoryItem", "measurement", "weight") == { "value" => 4.0, "unit" => "KILOGRAMS" } }
    end
  end

  test "creates the unique id-type metafield definition when missing" do
    Shopify::ProductImporter.call

    assert_equal "id", @shopify.definition_type
  end

  test "second run skips existing products and creates no duplicates" do
    Shopify::ProductImporter.call
    run = Shopify::ProductImporter.call

    assert_equal [ 0, 0, 3, 0 ], [ run.created_count, run.updated_count, run.skipped_count, run.failed_count ]
    assert_equal 3, @shopify.products.size
    assert_equal 3, @shopify.product_set_calls # no writes on the second run
    assert(run.results.all? { |r| r["image_url"].start_with?("https://cdn.shopify.com/") })
  end

  test "repairs a partially imported product instead of duplicating it" do
    @shopify.add_incomplete_product(2)

    run = Shopify::ProductImporter.call

    assert_equal [ 2, 1, 0, 0 ], [ run.created_count, run.updated_count, run.skipped_count, run.failed_count ]
    assert_equal "updated", run.results.find { |r| r["source_id"] == 2 }["outcome"]
    assert_equal 3, @shopify.products.size
  end

  test "records userErrors per product and continues with the rest" do
    @shopify.user_errors_for["2"] = [ { "field" => %w[input title], "message" => "Title can't be blank" } ]

    run = Shopify::ProductImporter.call

    assert_equal "completed_with_errors", run.status
    assert_equal [ 2, 1 ], [ run.created_count, run.failed_count ]
    failed = run.results.find { |r| r["outcome"] == "failed" }
    assert_equal [ "input.title: Title can't be blank" ], failed["messages"]
  end

  test "a failed product is created on the next run" do
    @shopify.user_errors_for["2"] = [ { "field" => nil, "message" => "Temporary failure" } ]
    Shopify::ProductImporter.call
    @shopify.user_errors_for.clear

    run = Shopify::ProductImporter.call

    assert_equal [ 1, 2, 0 ], [ run.created_count, run.skipped_count, run.failed_count ]
    assert_equal 3, @shopify.products.size
  end

  test "stops with a clear error if the metafield definition has the wrong type" do
    @shopify.definition_type = "single_line_text_field"

    run = Shopify::ProductImporter.call

    assert_equal "failed", run.status
    assert_match(/require type 'id'/, run.error_message)
    assert_empty @shopify.products
  end

  test "DummyJSON outage fails the run with a readable error" do
    stub_dummyjson(status: 503, body: "")

    run = Shopify::ProductImporter.call

    assert_equal "failed", run.status
    assert_match(/DummyJSON request failed/, run.error_message)
  end

  test "invalid credentials fail the run without exposing the secret" do
    WebMock.reset_executed_requests!
    stub_request(:post, ShopifyTestHelpers::TOKEN_URL).to_return(status: 401)

    run = Shopify::ProductImporter.call

    assert_equal "failed", run.status
    assert_match(/rejected the credentials/, run.error_message)
    assert_not_includes run.error_message, ShopifyTestHelpers::CLIENT_SECRET
  end

  test "refuses to run while another seed holds the lock" do
    with_seed_lock_held do
      assert_raises(Shopify::ProductImporter::AlreadyRunning) { Shopify::ProductImporter.call }
    end
    assert_empty @shopify.products
  end

  test "an unexpected error marks the run failed instead of leaving it running" do
    stub_request(:get, %r{dummyjson\.com}).to_raise(ArgumentError.new("boom"))

    assert_raises(ArgumentError) { Shopify::ProductImporter.call }
    run = SeedRun.recent.first
    assert_equal "failed", run.status
    assert_match(/Unexpected error \(ArgumentError\)/, run.error_message)
  end

  test "an unmapped DummyJSON category leaves the Shopify category out of the request" do
    input = Shopify::ProductImporter.new.send(:product_input,
      { "id" => 99, "title" => "Lamp", "price" => 10, "category" => "home-decoration", "thumbnail" => "https://x/y.webp" })

    assert_equal "Home Decoration", input[:productType]
    assert_not input.key?(:category)
  end
end
