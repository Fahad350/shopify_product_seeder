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
      if check_connection
        redirect_to edit_settings_path, notice: "Settings saved."
      else
        redirect_to edit_settings_path, alert: "Settings saved, but the connection failed: #{@setting.connection_message}"
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def test_connection
    setting = ShopSetting.current
    if setting.configured?
      @setting = setting
      check_connection
    end
    redirect_to edit_settings_path
  end

  private

  def setting_params
    params.require(:shop_setting).permit(:shop_domain, :client_id, :client_secret)
  end

  # Always requests a fresh token so the check reflects the saved credentials.
  # Returns true when Shopify issued a token.
  def check_connection
    Shopify::TokenService.new(@setting).refresh!
    @setting.record_connection!(ok: true, message: "Access token obtained via client credentials.")
    true
  rescue Shopify::TokenService::Error => e
    @setting.record_connection!(ok: false, message: e.message)
    false
  end
end
