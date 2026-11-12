require "test_helper"

class ShopSettingTest < ActiveSupport::TestCase
  test "encrypts the client secret at rest" do
    setting = create_setting

    raw = ShopSetting.connection.select_value("SELECT client_secret FROM shop_settings WHERE id = #{setting.id}")
    assert_not_includes raw, ShopifyTestHelpers::CLIENT_SECRET
    assert_equal ShopifyTestHelpers::CLIENT_SECRET, setting.reload.client_secret
  end

  test "normalizes the shop domain" do
    setting = create_setting(shop_domain: " https://Seeder-Test.myshopify.com/ ")

    assert_equal "seeder-test.myshopify.com", setting.shop_domain
  end

  test "requires a myshopify.com domain, client ID and secret" do
    setting = ShopSetting.new(shop_domain: "example.com")

    assert_not setting.valid?
    assert setting.errors.of_kind?(:shop_domain, :invalid)
    assert setting.errors.of_kind?(:client_id, :blank)
    assert setting.errors.of_kind?(:client_secret, :blank)
  end

  test "records connection status" do
    setting = create_setting
    setting.record_connection!(ok: false, message: "nope")

    assert_not setting.reload.connected?
    assert_equal "failed", setting.connection_status
  end
end
