# Single-row settings record holding the Shopify store credentials.
# The client secret is encrypted at rest with Active Record Encryption.
class ShopSetting < ApplicationRecord
  encrypts :client_secret

  DOMAIN_FORMAT = /\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/

  validates :shop_domain, presence: true, format: { with: DOMAIN_FORMAT, message: "must look like your-store.myshopify.com" }
  validates :client_id, presence: true
  validates :client_secret, presence: true

  before_validation :normalize_shop_domain

  def self.current
    first_or_initialize
  end

  def configured?
    persisted? && shop_domain.present? && client_id.present? && client_secret.present?
  end

  def connected?
    connection_status == "connected"
  end

  def record_connection!(ok:, message:)
    update_columns(
      connection_status: ok ? "connected" : "failed",
      connection_message: message,
      last_checked_at: Time.current
    )
  end

  private

  def normalize_shop_domain
    return if shop_domain.blank?

    self.shop_domain = shop_domain.strip.downcase.sub(%r{\Ahttps?://}, "").delete_suffix("/")
  end
end
