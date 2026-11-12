require "test_helper"

class DummyJson::ProductFetcherTest < ActiveSupport::TestCase
  test "fetches three products with the needed fields" do
    stub = stub_dummyjson

    products = DummyJson::ProductFetcher.new.call

    assert_equal 3, products.size
    assert_equal [ 1, 2, 3 ], products.map { |p| p["id"] }
    assert(products.all? { |p| p["title"].present? && p["price"].present? && p["thumbnail"].present? })
    assert_requested stub
    assert_requested :get, %r{dummyjson\.com/products\?limit=3}
  end

  test "HTTP failure raises a readable error" do
    stub_dummyjson(status: 500, body: "")

    error = assert_raises(DummyJson::ProductFetcher::Error) { DummyJson::ProductFetcher.new.call }
    assert_match(/HTTP 500/, error.message)
  end

  test "empty product list raises" do
    stub_dummyjson(body: { products: [] }.to_json)

    assert_raises(DummyJson::ProductFetcher::Error) { DummyJson::ProductFetcher.new.call }
  end

  test "invalid JSON raises a readable error" do
    stub_dummyjson(body: "not json")

    error = assert_raises(DummyJson::ProductFetcher::Error) { DummyJson::ProductFetcher.new.call }
    assert_match(/unreadable/, error.message)
  end
end
