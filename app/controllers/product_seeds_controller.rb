class ProductSeedsController < ApplicationController
  def index
    @setting = ShopSetting.current
    @run = SeedRun.recent.first
  end

  def create
    unless ShopSetting.current.configured?
      return redirect_to edit_settings_path, alert: "Save your Shopify settings before seeding."
    end

    run = Shopify::ProductImporter.call
    flash[:notice] = "Seed finished: #{run.created_count} created, #{run.updated_count} updated, " \
                     "#{run.skipped_count} skipped, #{run.failed_count} failed." unless run.status == "failed"
    flash[:alert] = run.error_message if run.status == "failed"
    redirect_to product_seeds_path
  rescue Shopify::ProductImporter::AlreadyRunning => e
    redirect_to product_seeds_path, alert: e.message
  end
end
