# Minimal in-memory stand-in for the Shopify Admin GraphQL endpoint, covering
# only the operations ProductImporter and ProductCatalog use.
# Products are keyed by DummyJSON ID.
class FakeShopify
  TAXONOMY_NAMES = { "gid://shopify/TaxonomyCategory/hb" => "Health & Beauty" }.freeze

  attr_reader :products, :product_set_calls
  attr_accessor :definition_type, :user_errors_for, :search_lag

  def initialize
    @products = {}
    @product_set_calls = 0
    @definition_type = nil # nil = no metafield definition yet
    @user_errors_for = {}  # source_id => [{ "field" => [...], "message" => "..." }]
    @next_id = 1000
  end

  def install(test)
    test.stub_request(:post, ShopifyTestHelpers::GRAPHQL_URL).to_return do |request|
      body = JSON.parse(request.body)
      test.json_response(data: respond(body["query"], body["variables"] || {}))
    end
  end

  # Simulates a partially imported product (e.g. its image failed).
  def add_incomplete_product(source_id)
    @products[source_id.to_s] = product_node(variants: 2, media: 0)
  end

  private

  def respond(query, vars)
    case query
    when /metafieldDefinitions\(/
      nodes = definition_type ? [ { "id" => "gid://shopify/MetafieldDefinition/1", "type" => { "name" => definition_type } } ] : []
      { "metafieldDefinitions" => { "nodes" => nodes } }
    when /metafieldDefinitionCreate/
      self.definition_type = vars.dig("definition", "type")
      { "metafieldDefinitionCreate" => { "createdDefinition" => { "id" => "gid://shopify/MetafieldDefinition/1" }, "userErrors" => [] } }
    when /productByIdentifier/
      { "productByIdentifier" => @products[vars.dig("identifier", "customId", "value")] }
    when /productSet/
      product_set(vars)
    when /query SeededProductsById/
      { "nodes" => vars["ids"].map { |id| @products.values.find { |p| p["id"] == id } } }
    when /query SeededProducts/
      # search_lag: like Shopify's search index right after a create (not searchable yet)
      { "products" => { "nodes" => search_lag ? [] : @products.values } }
    when /query SeededProduct\(/
      { "product" => @products.values.find { |p| p["id"] == vars["id"] } }
    else
      raise "FakeShopify: unexpected query #{query[0, 80]}"
    end
  end

  def product_set(vars)
    @product_set_calls += 1
    source_id = vars.dig("identifier", "customId", "value")
    if (errors = user_errors_for[source_id])
      return { "productSet" => { "product" => nil, "userErrors" => errors } }
    end

    input = vars["input"]
    node = (@products[source_id] || product_node).merge(
      "title" => input["title"],
      "variantsCount" => { "count" => input["variants"].size },
      "media" => { "nodes" => input["files"].map.with_index { |_, i| { "id" => "gid://shopify/MediaImage/#{i}" } } },
      "featuredMedia" => { "preview" => { "image" => { "url" => "https://cdn.shopify.com/fake/#{source_id}.webp" } } },
      "vendor" => input["vendor"], "productType" => input["productType"], "status" => input["status"],
      "category" => input["category"] && { "fullName" => TAXONOMY_NAMES.fetch(input["category"], "Unknown") },
      "tags" => input["tags"], "descriptionHtml" => input["descriptionHtml"], "createdAt" => "2026-11-12T08:00:00Z",
      "metafield" => { "value" => source_id },
      "variants" => { "nodes" => input["variants"].map.with_index do |v, i|
        { "id" => "gid://shopify/ProductVariant/#{@next_id}#{i}", "title" => v["optionValues"].first["name"],
          "price" => v["price"], "sku" => v["sku"], "compareAtPrice" => v["compareAtPrice"],
          "barcodes" => { "nodes" => Array(v["barcodes"]).map { |b| { "value" => b["value"] } } },
          "inventoryItem" => { "measurement" => { "weight" => v.dig("inventoryItem", "measurement", "weight") } },
          "selectedOptions" => v["optionValues"].map { |o| { "name" => o["optionName"], "value" => o["name"] } } }
      end }
    )
    @products[source_id] = node
    { "productSet" => { "product" => node, "userErrors" => [] } }
  end

  def product_node(variants: 2, media: 1)
    @next_id += 1
    {
      "id" => "gid://shopify/Product/#{@next_id}", "title" => "x", "handle" => "x",
      "variantsCount" => { "count" => variants },
      "media" => { "nodes" => Array.new(media) { |i| { "id" => "gid://shopify/MediaImage/#{i}" } } },
      "featuredMedia" => nil
    }
  end
end
