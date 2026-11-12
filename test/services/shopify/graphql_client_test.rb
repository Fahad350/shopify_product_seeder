require "test_helper"

class Shopify::GraphqlClientTest < ActiveSupport::TestCase
  URL = ShopifyTestHelpers::GRAPHQL_URL
  SHOP_QUERY = "{ shop { name } }".freeze

  setup do
    @setting = create_setting
    @client = Shopify::GraphqlClient.new(@setting)
  end

  test "sends the query with the cached access token and returns data" do
    stub_token("tok-1")
    stub_request(:post, URL)
      .with(headers: { "X-Shopify-Access-Token" => "tok-1" }, body: { query: SHOP_QUERY, variables: {} }.to_json)
      .to_return(json_response(data: { shop: { name: "Test Shop" } }))

    assert_equal({ "shop" => { "name" => "Test Shop" } }, @client.query(SHOP_QUERY))
  end

  test "HTTP 401 triggers a token refresh and exactly one retry" do
    token_stub = stub_token("expired-token", "fresh-token")
    stub_request(:post, URL).with(headers: { "X-Shopify-Access-Token" => "expired-token" }).to_return(status: 401)
    stub_request(:post, URL).with(headers: { "X-Shopify-Access-Token" => "fresh-token" })
      .to_return(json_response(data: { shop: { name: "Test Shop" } }))

    assert_equal "Test Shop", @client.query(SHOP_QUERY).dig("shop", "name")
    assert_requested token_stub, times: 2 # initial + one refresh
    assert_requested :post, URL, times: 2  # original + one retry
  end

  test "a second 401 after refreshing fails without further retries" do
    stub_token("tok-1", "tok-2")
    stub_request(:post, URL).to_return(status: 401)

    error = assert_raises(Shopify::GraphqlClient::AuthenticationError) { @client.query(SHOP_QUERY) }
    assert_match(/after a refresh/, error.message)
    assert_requested :post, URL, times: 2
  end

  test "token request failure surfaces as an authentication error" do
    stub_request(:post, ShopifyTestHelpers::TOKEN_URL).to_return(status: 401)

    assert_raises(Shopify::GraphqlClient::AuthenticationError) { @client.query(SHOP_QUERY) }
  end

  test "top-level GraphQL errors raise with their messages" do
    stub_token("tok-1")
    stub_request(:post, URL).to_return(json_response(errors: [ { message: "Field 'nope' doesn't exist on type 'QueryRoot'" } ]))

    error = assert_raises(Shopify::GraphqlClient::Error) { @client.query("{ nope }") }
    assert_equal "GraphQL error: Field 'nope' doesn't exist on type 'QueryRoot'", error.message
  end

  test "HTTP failures raise readable errors" do
    stub_token("tok-1")
    {
      403 => /Access denied.*scopes/,
      404 => /not found/,
      429 => /rate limit/,
      503 => /HTTP 503/
    }.each do |status, message|
      stub_request(:post, URL).to_return(status: status)
      error = assert_raises(Shopify::GraphqlClient::Error) { @client.query(SHOP_QUERY) }
      assert_match message, error.message
    end
  end

  test "timeouts raise a readable error" do
    stub_token("tok-1")
    stub_request(:post, URL).to_timeout

    error = assert_raises(Shopify::GraphqlClient::Error) { @client.query(SHOP_QUERY) }
    assert_match(/Could not reach Shopify/, error.message)
  end

  test "unparseable responses raise a readable error" do
    stub_token("tok-1")
    stub_request(:post, URL).to_return(status: 200, body: "<html>oops</html>")

    error = assert_raises(Shopify::GraphqlClient::Error) { @client.query(SHOP_QUERY) }
    assert_match(/unreadable/, error.message)
  end

  test "error messages never contain the access token or client secret" do
    stub_token("tok-SECRET-123")
    leaked = "bad token tok-SECRET-123 and secret #{ShopifyTestHelpers::CLIENT_SECRET}"
    stub_request(:post, URL).to_return(json_response(errors: [ { message: leaked } ]))

    error = assert_raises(Shopify::GraphqlClient::Error) { @client.query(SHOP_QUERY) }
    assert_not_includes error.message, "tok-SECRET-123"
    assert_not_includes error.message, ShopifyTestHelpers::CLIENT_SECRET
    assert_includes error.message, "[FILTERED]"
  end
end
