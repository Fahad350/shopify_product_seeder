require "test_helper"

class ProductsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_setting
    stub_token("tok-1")
    stub_dummyjson
    @shopify = FakeShopify.new
    @shopify.install(self)
  end

  test "products page lists seeded products with variant counts" do
    Shopify::ProductImporter.call

    get products_path

    assert_response :success
    assert_select "table.products-table tbody tr", 3
    assert_select ".product-title", "Essence Mascara Lash Princess"
    assert_select ".count-pill", "2"
  end

  test "products page shows an empty state before seeding" do
    get products_path

    assert_response :success
    assert_select ".empty strong", "No seeded products yet"
  end

  test "product page shows both variants with price and SKU" do
    Shopify::ProductImporter.call
    id = @shopify.products["1"]["id"].split("/").last

    get product_path(id)

    assert_response :success
    assert_select "h1", "Essence Mascara Lash Princess"
    assert_select "table.results tbody tr", 2
    assert_select "td.mono", "BEA-ESS-ESS-001-STD"
    assert_select "td.mono", "BEA-ESS-ESS-001-PRM"
    assert_match "$12.49", response.body
    assert_select "s.compare-at", "$11.16"      # compare-at (original) price
    assert_select "td.mono", "5784719087687"    # barcode on the Standard variant
    assert_match "4 kg", response.body           # weight
    assert_select "dd", "Health & Beauty"       # Shopify taxonomy category
  end

  test "unknown product redirects with a message" do
    get product_path("999999")

    assert_redirected_to products_path
    assert_match(/not found/, flash[:alert])
  end

  test "Shopify errors are shown instead of crashing" do
    WebMock.reset!
    stub_token("tok-1")
    stub_request(:post, ShopifyTestHelpers::GRAPHQL_URL).to_return(status: 503)

    get products_path

    assert_response :success
    assert_select ".flash-alert", /HTTP 503/
  end

  test "requires settings" do
    ShopSetting.delete_all

    get products_path

    assert_redirected_to edit_settings_path
  end

  test "products from the last seed appear before Shopify search indexes them" do
    Shopify::ProductImporter.call
    @shopify.search_lag = true

    get products_path

    assert_select "table.products-table tbody tr", 3
  end

  test "products list shows a spinner inside the auto-refresh frame while an image is processing" do
    Shopify::ProductImporter.call
    @shopify.products["2"]["featuredMedia"] = nil

    get products_path

    assert_select "turbo-frame#products_list[target='_top'][data-controller='thumb-refresh']" do
      assert_select ".thumb-pending", 1
      assert_select "img.thumb", 2
    end
  end

  test "product page shows a spinner while its image is processing" do
    Shopify::ProductImporter.call
    @shopify.products["1"]["featuredMedia"] = nil
    id = @shopify.products["1"]["id"].split("/").last

    get product_path(id)

    assert_select "turbo-frame#product_image[data-controller='thumb-refresh'] .thumb-pending", 1
  end
end
