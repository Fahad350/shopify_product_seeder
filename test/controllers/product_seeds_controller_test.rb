require "test_helper"

class ProductSeedsControllerTest < ActionDispatch::IntegrationTest
  test "dashboard prompts for settings before the store is configured" do
    get root_path

    assert_response :success
    assert_select "a", "Configure settings"
  end

  test "seeding without settings redirects to the settings page" do
    post product_seeds_path

    assert_redirected_to edit_settings_path
  end

  test "Seed Store imports products and shows counts and results" do
    create_setting
    stub_token("tok-1")
    stub_dummyjson
    FakeShopify.new.install(self)

    post product_seeds_path
    assert_redirected_to product_seeds_path
    follow_redirect!

    assert_match(/3 created/, flash[:notice])
    assert_select ".stat-created .stat-num", "3"
    assert_select ".stat-failed .stat-num", "0"
    assert_select "table.results tbody tr", 3
  end

  test "GraphQL userErrors appear in the UI" do
    create_setting
    stub_token("tok-1")
    stub_dummyjson
    shopify = FakeShopify.new
    shopify.user_errors_for["1"] = [ { "field" => %w[input title], "message" => "Title can't be blank" } ]
    shopify.install(self)

    post product_seeds_path
    follow_redirect!

    assert_select ".stat-failed .stat-num", "1"
    assert_select ".msg-error", "input.title: Title can't be blank"
  end

  test "a concurrent seed shows a friendly message" do
    create_setting
    with_seed_lock_held { post product_seeds_path }

    assert_redirected_to product_seeds_path
    assert_match(/already running/, flash[:alert])
  end

  test "dashboard thumbnails use the current Shopify image, not the stored fallback" do
    create_setting
    stub_token("tok-1")
    stub_dummyjson
    FakeShopify.new.install(self)
    run = Shopify::ProductImporter.call
    # As if the image was still processing at seed time.
    run.results.each { |r| r["image_url"] = "https://cdn.dummyjson.com/fallback.webp" }
    run.save!

    get product_seeds_path

    assert_select "img.thumb[src^='https://cdn.shopify.com/']", 3
    assert_select "img.thumb[src*='dummyjson']", 0
  end

  test "dashboard still renders stored thumbnails when Shopify is unreachable" do
    create_setting
    stub_token("tok-1")
    stub_dummyjson
    FakeShopify.new.install(self)
    Shopify::ProductImporter.call
    WebMock.reset!
    stub_token("tok-1")
    stub_request(:post, ShopifyTestHelpers::GRAPHQL_URL).to_return(status: 503)

    get product_seeds_path

    assert_response :success
    assert_select "table.results tbody tr", 3
    assert_select "tr.row-deleted", 0 # can't check Shopify, so nothing is marked deleted
    assert_select "a.shopify-link", 3
  end

  test "products deleted in Shopify are marked in the last run, without a broken link" do
    create_setting
    stub_token("tok-1")
    stub_dummyjson
    shopify = FakeShopify.new
    shopify.install(self)
    Shopify::ProductImporter.call
    shopify.products.delete("2") # deleted in the Shopify admin after the run

    get product_seeds_path

    assert_select "table.results tbody tr", 3 # history is kept
    assert_select "tr.row-deleted", 1
    assert_select "tr.row-deleted .deleted-note", "Deleted in Shopify"
    assert_select "tr.row-deleted a.shopify-link", 0
    assert_select "a.shopify-link", 2
    assert_select ".stat-created .stat-num", "3" # counts still match the run
  end

  test "thumbnails still processing in Shopify show a spinner inside the auto-refresh frame" do
    create_setting
    stub_token("tok-1")
    stub_dummyjson
    shopify = FakeShopify.new
    shopify.install(self)
    Shopify::ProductImporter.call
    shopify.products["1"]["featuredMedia"] = nil # image not processed yet

    get product_seeds_path

    assert_select "turbo-frame#last_run[data-controller='thumb-refresh']" do
      assert_select ".thumb-pending", 1
      assert_select "img.thumb", 2
    end
    assert_select "img.thumb[src*='dummyjson']", 0 # no blocked fallback while processing
  end
end
