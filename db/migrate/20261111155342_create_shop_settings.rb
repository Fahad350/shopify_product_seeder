class CreateShopSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_settings do |t|
      t.string :shop_domain
      t.string :client_id
      t.text :client_secret
      t.string :connection_status
      t.string :connection_message
      t.datetime :last_checked_at

      t.timestamps
    end
  end
end
