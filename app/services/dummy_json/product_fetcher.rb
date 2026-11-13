require "net/http"

module DummyJson
  # Fetches source products from https://dummyjson.com/products.
  class ProductFetcher
    class Error < StandardError; end

    BASE_URL = "https://dummyjson.com/products".freeze
    FIELDS = %w[id title description price discountPercentage sku brand category tags weight meta thumbnail images].freeze
    TIMEOUT = 10

    def initialize(limit: 3)
      @limit = limit
    end

    # Returns an array of product hashes with string keys.
    def call
      uri = URI(BASE_URL)
      uri.query = URI.encode_www_form(limit: @limit, select: FIELDS.join(","))

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.get(uri.request_uri, "Accept" => "application/json")
      end
      raise Error, "DummyJSON request failed (HTTP #{response.code})." unless response.is_a?(Net::HTTPSuccess)

      products = JSON.parse(response.body).fetch("products")
      raise Error, "DummyJSON returned no products." if products.empty?

      products.first(@limit)
    rescue JSON::ParserError, KeyError
      raise Error, "DummyJSON returned an unreadable response."
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      raise Error, "Could not reach DummyJSON (#{e.class.name.demodulize})."
    end
  end
end
