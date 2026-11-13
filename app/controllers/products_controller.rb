# Read-only pages listing the seeded products and their variants, live from Shopify.
class ProductsController < ApplicationController
  before_action :require_settings

  def index
    @products = catalog.all(also_ids: last_run_product_ids)
  rescue Shopify::GraphqlClient::Error => e
    @products = []
    @error = e.message
  end

  def show
    @product = catalog.find(params[:id])
    redirect_to products_path, alert: "Product not found. It may have been deleted in Shopify." unless @product
  rescue Shopify::GraphqlClient::Error => e
    redirect_to products_path, alert: e.message
  end

  private

  def catalog
    @catalog ||= Shopify::ProductCatalog.new
  end

  # Products from the latest seed, so they show right away (see ProductCatalog#all).
  def last_run_product_ids
    Array(SeedRun.recent.first&.results).filter_map { |r| r["shopify_id"].presence }.uniq
  end

  def require_settings
    @setting = ShopSetting.current
    redirect_to edit_settings_path, alert: "Save your Shopify settings first." unless @setting.configured?
  end
end
