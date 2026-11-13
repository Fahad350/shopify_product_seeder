class ProductSeedsController < ApplicationController
  def index
    @setting = ShopSetting.current
    @run = SeedRun.recent.first
    @live_products = live_products if @run && @setting.configured?
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

  # Seeded products that currently exist in Shopify: { product_gid => image_url or nil }.
  # Used to show the current image (a new product's image is still processing when
  # the seed finishes) and to mark products deleted in Shopify since the run.
  # Returns nil if Shopify can't be reached, so nothing is wrongly marked deleted.
  def live_products
    Shopify::ProductCatalog.new.all.to_h { |p| [ p["id"], p.dig("featuredMedia", "preview", "image", "url") ] }
  rescue Shopify::GraphqlClient::Error
    nil
  end
end
