module ApplicationHelper
  # Small inline SVG icons (no icon library needed).
  ICONS = {
    dashboard: '<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
    tag: '<path d="M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
    box: '<path d="M21 8 12 3 3 8v8l9 5 9-5V8z"/><path d="m3 8 9 5 9-5"/><path d="M12 13v8"/>',
    store: '<path d="M3 9 4.5 4h15L21 9"/><path d="M4 9v11h16V9"/><path d="M3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0"/>'
  }.freeze

  def icon(name, size: 18)
    tag.svg(ICONS.fetch(name).html_safe, width: size, height: size, viewBox: "0 0 24 24", fill: "none",
            stroke: "currentColor", "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round",
            "aria-hidden": true, class: "icon")
  end

  def nav_link(label, path, icon_name, active:)
    link_to path, class: [ "nav-item", ("active" if active) ], "aria-current": (active ? "page" : nil) do
      safe_join([ icon(icon_name), tag.span(label) ])
    end
  end

  # => { css:, icon:, title:, message: } for the Settings connection card.
  def connection_state(setting)
    if !setting.persisted?
      { css: "status-none", icon: "–", title: "Not configured", message: "Save your credentials to connect." }
    elsif setting.connected?
      { css: "status-ok", icon: "✓", title: "Connected", message: setting.connection_message }
    elsif setting.connection_status == "failed"
      { css: "status-err", icon: "!", title: "Connection failed", message: setting.connection_message }
    else
      { css: "status-none", icon: "?", title: "Not checked", message: "Test the connection to verify your credentials." }
    end
  end

  def connection_dot_class(setting)
    return "dot-ok" if setting.connected?

    setting.connection_status == "failed" ? "dot-err" : ""
  end

  def run_status_badge_class(status)
    { "completed" => "badge-ok", "completed_with_errors" => "badge-warn", "failed" => "badge-error" }.fetch(status, "badge-muted")
  end

  def product_status_badge_class(status)
    { "ACTIVE" => "badge-ok", "DRAFT" => "badge-warn", "ARCHIVED" => "badge-muted" }.fetch(status.to_s, "badge-muted")
  end

  def weight_unit_label(unit)
    { "KILOGRAMS" => "kg", "GRAMS" => "g", "POUNDS" => "lb", "OUNCES" => "oz" }.fetch(unit.to_s, unit.to_s.downcase)
  end

  # "gid://shopify/Product/123" -> "123" (used in our own URLs).
  def product_numeric_id(product)
    product["id"].to_s.split("/").last
  end

  def product_thumb(product)
    url = product.dig("featuredMedia", "preview", "image", "url")
    return tag.span(class: "thumb") if url.blank?

    tag.img(class: "thumb", src: url, alt: "", loading: "lazy", onerror: "this.removeAttribute('src')")
  end

  # Link to a product in the Shopify admin (admin.shopify.com/store/<handle>/products/<id>).
  def shopify_admin_product_url(setting, product_gid)
    store = setting.shop_domain.delete_suffix(".myshopify.com")
    "https://admin.shopify.com/store/#{store}/products/#{product_gid.split('/').last}"
  end
end
