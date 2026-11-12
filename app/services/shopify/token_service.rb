require "net/http"

module Shopify
  # Obtains Admin API access tokens with the client-credentials grant and
  # caches them in Rails.cache until shortly before they expire.
  class TokenService
    class Error < StandardError; end

    EXPIRY_MARGIN = 5.minutes
    TIMEOUT = 10

    def initialize(setting = ShopSetting.current)
      @setting = setting
    end

    def token
      Rails.cache.read(cache_key) || fetch_and_cache
    end

    def refresh!
      Rails.cache.delete(cache_key)
      fetch_and_cache
    end

    private

    attr_reader :setting

    def fetch_and_cache
      data = request_token
      ttl = [data.fetch("expires_in", 3600).to_i.seconds - EXPIRY_MARGIN, 1.minute].max
      Rails.cache.write(cache_key, data.fetch("access_token"), expires_in: ttl)
      data.fetch("access_token")
    end

    def request_token
      uri = URI("https://#{setting.shop_domain}/admin/oauth/access_token")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.post(uri.path, URI.encode_www_form(
          grant_type: "client_credentials",
          client_id: setting.client_id,
          client_secret: setting.client_secret
        ), "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json")
      end

      case response
      when Net::HTTPSuccess
        JSON.parse(response.body).tap do |data|
          raise Error, "Shopify returned no access token" if data["access_token"].blank?
        end
      when Net::HTTPBadRequest, Net::HTTPUnauthorized, Net::HTTPForbidden
        raise Error, "Shopify rejected the credentials (HTTP #{response.code}). Check the client ID, client secret, and that the app is installed on this store."
      when Net::HTTPNotFound
        raise Error, "Store not found (HTTP 404). Check the shop domain."
      else
        raise Error, "Token request failed (HTTP #{response.code})."
      end
    rescue JSON::ParserError
      raise Error, "Shopify returned an unreadable token response."
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      raise Error, "Could not reach #{setting.shop_domain} (#{e.class.name.demodulize})."
    end

    # Keyed by store + client so changing credentials never reuses an old token.
    def cache_key
      "shopify/access_token/#{setting.shop_domain}/#{Digest::SHA256.hexdigest(setting.client_id.to_s)[0, 16]}"
    end
  end
end
