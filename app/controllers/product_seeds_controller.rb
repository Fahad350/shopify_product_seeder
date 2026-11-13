class ProductSeedsController < ApplicationController
  def index
    @setting = ShopSetting.current
    @run = SeedRun.recent.first
    @live_images = @run && @setting.configured? ? live_images : {}
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

  # Current Shopify image per product ({ product_gid => url }). A freshly created
  # product's image is still processing when the seed finishes, so the stored URL
  # is only a fallback. Thumbnails are optional: on any Shopify error, use none.
  def live_images
    Shopify::ProductCatalog.new.all
      .to_h { |p| [ p["id"], p.dig("featuredMedia", "preview", "image", "url") ] }
      .compact
  rescue Shopify::GraphqlClient::Error
    {}
  end
end
