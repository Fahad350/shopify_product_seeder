class ProductSeedsController < ApplicationController
  def index
    @setting = ShopSetting.current
    @run = SeedRun.recent.first
    return unless @run

    @live_products = live_products if @setting.configured?
    @results = results_still_in_shopify
    # Every product from the last run was deleted in Shopify: show the empty state,
    # like the Products page does.
    @run = nil if @results.empty? && @run.results.any?
  end

  def create
    unless ShopSetting.current.configured?
      return redirect_to edit_settings_path, alert: "Save your Shopify settings before seeding."
    end

    run = Shopify::ProductImporter.call
    if run.status == "failed"
      flash[:alert] = run.error_message
    else
      flash[:notice] = "Seed finished: #{run.created_count} created, #{run.updated_count} updated, " \
                       "#{run.skipped_count} skipped, #{run.failed_count} failed."
    end
    redirect_to product_seeds_path
  rescue Shopify::ProductImporter::AlreadyRunning => e
    redirect_to product_seeds_path, alert: e.message
  end

  private

  # Last-run rows, minus products deleted in Shopify since the run. Failed rows have
  # no Shopify product and are always kept. If Shopify can't be checked, keep all rows.
  def results_still_in_shopify
    return @run.results unless @live_products

    @run.results.reject { |r| r["shopify_id"].present? && !@live_products.key?(r["shopify_id"]) }
  end

  # The last run's products that still exist in Shopify: { product_gid => image_url or nil }.
  # Looked up by ID (not search), so products created a moment ago are found too.
  # Used to show the current image (a new product's image is still processing when
  # the seed finishes) and to hide products deleted in Shopify since the run.
  # Returns nil if Shopify can't be reached, so no row is wrongly hidden.
  def live_products
    gids = @run.results.filter_map { |r| r["shopify_id"].presence }.uniq
    Shopify::ProductCatalog.new.find_by_ids(gids)
      .transform_values { |p| p.dig("featuredMedia", "preview", "image", "url") }
  rescue Shopify::GraphqlClient::Error
    nil
  end
end
