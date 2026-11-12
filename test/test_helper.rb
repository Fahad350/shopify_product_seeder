ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

# No test may reach the real Shopify or DummyJSON.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Serial: the importer's Postgres advisory lock is shared across processes.
    parallelize(workers: 1)

    fixtures :all

    include ShopifyTestHelpers

    setup { Rails.cache.clear }
  end
end
