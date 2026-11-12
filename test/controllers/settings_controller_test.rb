require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "never renders the stored client secret" do
    create_setting

    get edit_settings_path

    assert_response :success
    assert_not_includes response.body, ShopifyTestHelpers::CLIENT_SECRET
    assert_includes response.body, ShopifyTestHelpers::SHOP
  end

  test "saving valid credentials checks the connection and shows Connected" do
    stub_token("tok-1")

    patch settings_path, params: { shop_setting: { shop_domain: ShopifyTestHelpers::SHOP, client_id: "cid", client_secret: "sec" } }

    assert_redirected_to edit_settings_path
    assert ShopSetting.current.connected?
    follow_redirect!
    assert_select ".status strong", "Connected"
  end

  test "invalid credentials show a failed status with a readable message" do
    stub_request(:post, ShopifyTestHelpers::TOKEN_URL).to_return(status: 401)

    patch settings_path, params: { shop_setting: { shop_domain: ShopifyTestHelpers::SHOP, client_id: "cid", client_secret: "wrong" } }
    follow_redirect!

    assert_select ".status strong", "Connection failed"
    assert_match(/rejected the credentials/, response.body)
  end

  test "a blank secret keeps the stored one" do
    create_setting
    stub_token("tok-1")

    patch settings_path, params: { shop_setting: { shop_domain: ShopifyTestHelpers::SHOP, client_id: "client-id-abc", client_secret: "" } }

    assert_equal ShopifyTestHelpers::CLIENT_SECRET, ShopSetting.current.client_secret
  end

  test "invalid input re-renders the form with errors" do
    patch settings_path, params: { shop_setting: { shop_domain: "not-a-shop", client_id: "", client_secret: "" } }

    assert_response :unprocessable_entity
    assert_select ".flash-alert li", minimum: 1
  end

  test "the client secret is filtered from request logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("shop_setting" => { "client_secret" => "sec", "client_id" => "cid" })

    assert_equal "[FILTERED]", filtered.dig("shop_setting", "client_secret")
    assert_equal "cid", filtered.dig("shop_setting", "client_id")
  end
end
