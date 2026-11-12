class SettingsController < ApplicationController
  def edit
    @setting = ShopSetting.current
  end

  def update
    @setting = ShopSetting.current
    attrs = setting_params
    # A blank secret field means "keep the stored secret".
    attrs = attrs.except(:client_secret) if attrs[:client_secret].blank? && @setting.persisted?

    if @setting.update(attrs)
      check_connection
      redirect_to edit_settings_path, notice: "Settings saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def test_connection
    setting = ShopSetting.current
    if setting.configured?
      @setting = setting
      check_connection(force_refresh: true)
    end
    redirect_to edit_settings_path
  end

  private

  def setting_params
    params.require(:shop_setting).permit(:shop_domain, :client_id, :client_secret)
  end

  def check_connection(force_refresh: true)
    service = Shopify::TokenService.new(@setting)
    force_refresh ? service.refresh! : service.token
    @setting.record_connection!(ok: true, message: "Access token obtained via client credentials.")
  rescue Shopify::TokenService::Error => e
    @setting.record_connection!(ok: false, message: e.message)
  end
end
