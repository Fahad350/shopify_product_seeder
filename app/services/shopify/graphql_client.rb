require "net/http"

module Shopify
  # Thin Admin GraphQL client.
  #
  # - Authenticates with a cached client-credentials token (TokenService).
  # - On HTTP 401 it refreshes the token and retries exactly once.
  # - Raises Shopify::GraphqlClient::Error for HTTP failures, timeouts and
  #   top-level GraphQL errors. Mutation `userErrors` are returned as data so
  #   callers can report them per record.
  # - Error messages never contain the access token or client secret.
  class GraphqlClient
    class Error < StandardError; end
    class AuthenticationError < Error; end

    API_VERSION = ENV.fetch("SHOPIFY_API_VERSION", "2026-10")
    TIMEOUT = 20

    def initialize(setting = ShopSetting.current, token_service: TokenService.new(setting))
      @setting = setting
      @token_service = token_service
    end

    # Returns the `data` hash of the response.
    def query(query, variables = {})
      response = post(query, variables, token_service.token)

      if response.is_a?(Net::HTTPUnauthorized)
        # Cached token was revoked or expired early: refresh once and retry once.
        response = post(query, variables, token_service.refresh!)
        raise AuthenticationError, "Shopify rejected the access token after a refresh (HTTP 401)." if response.is_a?(Net::HTTPUnauthorized)
      end

      handle(response)
    rescue TokenService::Error => e
      raise AuthenticationError, sanitize(e.message)
    end

    private

    attr_reader :setting, :token_service

    def endpoint
      @endpoint ||= URI("https://#{setting.shop_domain}/admin/api/#{API_VERSION}/graphql.json")
    end

    def post(query, variables, token)
      Net::HTTP.start(endpoint.host, endpoint.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.post(endpoint.path, { query: query, variables: variables }.to_json,
                  "Content-Type" => "application/json",
                  "Accept" => "application/json",
                  "X-Shopify-Access-Token" => token)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise Error, "Could not reach Shopify (#{e.class.name.demodulize})."
    end

    def handle(response)
      raise Error, http_error_message(response) unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      if body["errors"].present?
        raise Error, "GraphQL error: #{sanitize(format_errors(body['errors']))}"
      end

      body.fetch("data")
    rescue JSON::ParserError, KeyError
      raise Error, "Shopify returned an unreadable GraphQL response."
    end

    def http_error_message(response)
      case response
      when Net::HTTPForbidden then "Access denied (HTTP 403). Check the app's API scopes."
      when Net::HTTPNotFound then "Shopify API not found (HTTP 404). Check the shop domain and API version #{API_VERSION}."
      when Net::HTTPTooManyRequests then "Shopify rate limit reached (HTTP 429). Try again shortly."
      else "Shopify API request failed (HTTP #{response.code})."
      end
    end

    def format_errors(errors)
      Array(errors).map { |e| e.is_a?(Hash) ? e["message"] : e.to_s }.compact.join("; ")
    end

    def sanitize(message)
      secrets = [ setting.client_secret, token_service.cached_token ].compact_blank
      secrets.reduce(message.to_s) { |msg, secret| msg.gsub(secret, "[FILTERED]") }
    end
  end
end
