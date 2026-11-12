require "test_helper"

class Shopify::TokenServiceTest < ActiveSupport::TestCase
  setup do
    @setting = create_setting
    @service = Shopify::TokenService.new(@setting)
  end

  test "requests a token with the client-credentials grant" do
    stub = stub_token("tok-1")

    assert_equal "tok-1", @service.token
    assert_requested(:post, ShopifyTestHelpers::TOKEN_URL) do |req|
      form = URI.decode_www_form(req.body).to_h
      form == { "grant_type" => "client_credentials", "client_id" => "client-id-abc", "client_secret" => ShopifyTestHelpers::CLIENT_SECRET }
    end
    assert_requested stub, times: 1
  end

  test "caches the token in Rails.cache and avoids repeat token requests" do
    stub = stub_token("tok-1")

    3.times { assert_equal "tok-1", @service.token }
    assert_equal "tok-1", Shopify::TokenService.new(@setting).token # new instance, same cache
    assert_requested stub, times: 1
  end

  test "requests a new token once the cached one expires" do
    stub = stub_token("tok-1", "tok-2", expires_in: 3600)

    assert_equal "tok-1", @service.token
    travel 56.minutes do # 60 min lifetime minus the 5 min safety margin has passed
      assert_equal "tok-2", @service.token
    end
    assert_requested stub, times: 2
  end

  test "refresh! replaces the cached token" do
    stub_token("tok-1", "tok-2")

    assert_equal "tok-1", @service.token
    assert_equal "tok-2", @service.refresh!
    assert_equal "tok-2", @service.token
    assert_equal "tok-2", @service.cached_token
  end

  test "invalid credentials raise a readable error without the secret" do
    stub_request(:post, ShopifyTestHelpers::TOKEN_URL).to_return(status: 400, body: { error: "invalid_client" }.to_json)

    error = assert_raises(Shopify::TokenService::Error) { @service.token }
    assert_match(/rejected the credentials/, error.message)
    assert_not_includes error.message, ShopifyTestHelpers::CLIENT_SECRET
  end

  test "unknown store raises a readable error" do
    stub_request(:post, ShopifyTestHelpers::TOKEN_URL).to_return(status: 404)

    error = assert_raises(Shopify::TokenService::Error) { @service.token }
    assert_match(/Store not found/, error.message)
  end

  test "connection reset raises a readable error" do
    stub_request(:post, ShopifyTestHelpers::TOKEN_URL).to_raise(Errno::ECONNRESET)

    error = assert_raises(Shopify::TokenService::Error) { @service.token }
    assert_match(/Could not reach .*ECONNRESET/, error.message)
  end

  test "network timeout raises a readable error" do
    stub_request(:post, ShopifyTestHelpers::TOKEN_URL).to_timeout

    error = assert_raises(Shopify::TokenService::Error) { @service.token }
    assert_match(/Could not reach/, error.message)
  end

  test "changing credentials does not reuse another client's cached token" do
    stub_token("tok-1", "tok-2")

    assert_equal "tok-1", @service.token
    other = ShopSetting.new(shop_domain: @setting.shop_domain, client_id: "different-client", client_secret: "x")
    assert_equal "tok-2", Shopify::TokenService.new(other).token
  end
end
