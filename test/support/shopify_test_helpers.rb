module ShopifyTestHelpers
  SHOP = "seeder-test.myshopify.com".freeze
  CLIENT_SECRET = "shhh-client-secret-123".freeze
  TOKEN_URL = "https://#{SHOP}/admin/oauth/access_token".freeze
  GRAPHQL_URL = "https://#{SHOP}/admin/api/#{Shopify::GraphqlClient::API_VERSION}/graphql.json".freeze

  def create_setting(**attrs)
    ShopSetting.create!({ shop_domain: SHOP, client_id: "client-id-abc", client_secret: CLIENT_SECRET }.merge(attrs))
  end

  def stub_token(*tokens, expires_in: 86_399)
    responses = tokens.map do |t|
      { status: 200, body: { access_token: t, scope: "write_products", expires_in: expires_in }.to_json,
        headers: { "Content-Type" => "application/json" } }
    end
    stub_request(:post, TOKEN_URL).to_return(*responses)
  end

  def stub_dummyjson(body: file_fixture("dummyjson_products.json").read, status: 200)
    stub_request(:get, %r{\Ahttps://dummyjson\.com/products}).to_return(status: status, body: body)
  end

  # Holds the seeder's advisory lock from a separate DB session, as if another
  # seed were already in progress.
  def with_seed_lock_held
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect({ host: cfg[:host], port: cfg[:port], dbname: cfg[:database],
                         user: cfg[:username], password: cfg[:password] }.compact)
    other.exec("SELECT pg_advisory_lock(#{Shopify::ProductImporter::LOCK_ID})")
    yield
  ensure
    other&.close
  end

  # json_response(data: {...}) or json_response({ errors: [...] }, status: 200)
  def json_response(hash = nil, status: 200, **payload)
    { status: status, body: (hash || payload).to_json, headers: { "Content-Type" => "application/json" } }
  end
end
