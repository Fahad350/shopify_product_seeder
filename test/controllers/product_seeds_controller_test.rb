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
end
