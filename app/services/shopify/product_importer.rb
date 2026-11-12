module Shopify
  # Imports DummyJSON products into Shopify with Admin GraphQL `productSet`.
  #
  # Idempotency: each product carries its DummyJSON ID in the metafield
  # seeder.dummyjson_id. The metafield definition has the "unique values"
  # capability, so `productSet(identifier: { customId: ... })` upserts on that
  # ID and Shopify itself can never hold two products with the same source ID.
  #
  # Per product:
  #   - missing                 -> created
  #   - exists and complete     -> skipped (no write)
  #   - exists but incomplete   -> updated (repairs a partial earlier import)
  #   - any error               -> failed, with the GraphQL/HTTP messages
  #
  # Concurrency: a Postgres advisory lock lets only one seed run at a time.
  class ProductImporter
    class AlreadyRunning < StandardError; end

    NAMESPACE = "seeder".freeze
    KEY = "dummyjson_id".freeze
    LOCK_ID = 20_261_110 # arbitrary, app-wide
    VARIANTS = [
      { name: "Standard", price_factor: 1.0, sku_suffix: "STD" },
      { name: "Premium", price_factor: 1.25, sku_suffix: "PRM" }
    ].freeze

    # Product fields read after a lookup or write: used for the completeness
    # check (2 variants + an image) and the dashboard thumbnail.
    PRODUCT_FIELDS = <<~GQL.freeze
      id title handle
      variantsCount { count }
      media(first: 1) { nodes { id } }
      featuredMedia { preview { image { url(transform: { maxWidth: 120, maxHeight: 120 }) } } }
    GQL

    FIND_QUERY = <<~GQL.freeze
      query FindSeededProduct($identifier: ProductIdentifierInput!) {
        productByIdentifier(identifier: $identifier) { #{PRODUCT_FIELDS} }
      }
    GQL

    PRODUCT_SET = <<~GQL.freeze
      mutation SeedProduct($input: ProductSetInput!, $identifier: ProductSetIdentifiers) {
        productSet(input: $input, identifier: $identifier, synchronous: true) {
          product { #{PRODUCT_FIELDS} }
          userErrors { field message code }
        }
      }
    GQL

    DEFINITION_QUERY = <<~GQL.freeze
      query { metafieldDefinitions(first: 1, ownerType: PRODUCT, namespace: "#{NAMESPACE}", key: "#{KEY}") { nodes { id type { name } } } }
    GQL

    DEFINITION_CREATE = <<~GQL.freeze
      mutation CreateSeederDefinition($definition: MetafieldDefinitionInput!) {
        metafieldDefinitionCreate(definition: $definition) {
          createdDefinition { id }
          userErrors { field message code }
        }
      }
    GQL

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(client: GraphqlClient.new, fetcher: DummyJson::ProductFetcher.new)
      @client = client
      @fetcher = fetcher
    end

    # Returns a saved SeedRun. Raises AlreadyRunning if another seed holds the lock.
    def call
      with_lock do
        run = SeedRun.create!(status: "running")
        begin
          ensure_metafield_definition!
          @fetcher.call.each { |source| run.add_result(import(source)) }
          run.finish!
        rescue GraphqlClient::Error, DummyJson::ProductFetcher::Error => e
          run.finish!(error: e.message)
        rescue StandardError => e
          # Never leave a run stuck in "running"; the details go to the log, not the UI.
          run.finish!(error: "Unexpected error (#{e.class.name}). See the application log.")
          raise
        end
        run
      end
    end

    private

    attr_reader :client

    def import(source)
      base = { source_id: source["id"], title: source["title"], image_url: source["thumbnail"], messages: [] }
      existing = find_existing(source["id"])

      if existing && complete?(existing)
        return base.merge(outcome: "skipped", shopify_id: existing["id"], image_url: image_url(existing, source),
                          messages: [ "Already imported." ])
      end

      payload = client.query(PRODUCT_SET, input: product_input(source), identifier: identifier(source["id"]))["productSet"]
      errors = payload["userErrors"]
      if errors.present?
        return base.merge(outcome: "failed", shopify_id: existing&.dig("id"), messages: errors.map { |e| format_user_error(e) })
      end

      product = payload["product"]
      base.merge(outcome: existing ? "updated" : "created", shopify_id: product&.dig("id"),
                 image_url: image_url(product, source),
                 messages: existing ? [ "Existing product was incomplete and has been repaired." ] : [])
    rescue GraphqlClient::AuthenticationError
      raise # credentials problem: stop the whole run
    rescue GraphqlClient::Error => e
      base.merge(outcome: "failed", messages: [ e.message ]) # keep going with the next product
    end

    def find_existing(source_id)
      client.query(FIND_QUERY, identifier: identifier(source_id))["productByIdentifier"]
    end

    # Prefer the image as stored on Shopify's CDN; a freshly uploaded image may
    # still be processing, so fall back to the DummyJSON source image.
    def image_url(product, source)
      product&.dig("featuredMedia", "preview", "image", "url").presence || source["thumbnail"]
    end

    def complete?(product)
      product.dig("variantsCount", "count") == VARIANTS.size && product.dig("media", "nodes").present?
    end

    def identifier(source_id)
      { customId: { namespace: NAMESPACE, key: KEY, value: source_id.to_s } }
    end

    def product_input(source)
      base_price = source["price"].to_d
      base_sku = source["sku"].presence || "DJ-#{source['id']}"

      {
        title: source["title"],
        descriptionHtml: ERB::Util.html_escape(source["description"].to_s),
        vendor: source["brand"].presence || "DummyJSON",
        productType: source["category"].to_s.titleize,
        status: "ACTIVE",
        tags: [ "dummyjson", "seeded" ],
        productOptions: [ { name: "Edition", values: VARIANTS.map { |v| { name: v[:name] } } } ],
        variants: VARIANTS.map do |v|
          {
            optionValues: [ { optionName: "Edition", name: v[:name] } ],
            price: (base_price * v[:price_factor]).round(2).to_s("F"),
            sku: "#{base_sku}-#{v[:sku_suffix]}"
          }
        end,
        files: [ { originalSource: source["thumbnail"], contentType: "IMAGE", alt: source["title"] } ]
        # The DummyJSON ID metafield is written by productSet from the customId identifier.
      }
    end

    def ensure_metafield_definition!
      existing = client.query(DEFINITION_QUERY).dig("metafieldDefinitions", "nodes").first
      if existing
        return if existing.dig("type", "name") == "id"

        raise GraphqlClient::Error, "Metafield definition #{NAMESPACE}.#{KEY} exists with type " \
                                    "'#{existing.dig('type', 'name')}', but custom IDs require type 'id'. Delete it in Shopify admin and seed again."
      end

      payload = client.query(DEFINITION_CREATE, definition: {
        name: "DummyJSON ID",
        namespace: NAMESPACE,
        key: KEY,
        type: "id",
        ownerType: "PRODUCT",
        capabilities: { uniqueValues: { enabled: true } }
      })["metafieldDefinitionCreate"]

      errors = payload["userErrors"].reject { |e| e["code"] == "TAKEN" } # created concurrently: fine
      raise GraphqlClient::Error, "Could not create metafield definition: #{errors.map { |e| format_user_error(e) }.join('; ')}" if errors.any?
    end

    def format_user_error(error)
      field = Array(error["field"]).join(".")
      field.present? ? "#{field}: #{error['message']}" : error["message"].to_s
    end

    def with_lock
      conn = ActiveRecord::Base.connection
      raise AlreadyRunning, "A seed is already running. Please wait for it to finish." unless conn.select_value("SELECT pg_try_advisory_lock(#{LOCK_ID})")

      begin
        yield
      ensure
        conn.select_value("SELECT pg_advisory_unlock(#{LOCK_ID})")
      end
    end
  end
end
