class CreateCompanies < ActiveRecord::Migration[8.0]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :subdomain, null: false
      t.string :domain
      t.string :phone
      t.string :email
      t.text :address
      t.string :city
      t.string :state
      t.string :zip_code
      t.string :timezone, default: 'America/Phoenix'
      t.boolean :active, default: true
      t.jsonb :settings, default: {}
      t.string :logo_url
      t.string :primary_color
      t.string :secondary_color
      t.text :description
      t.string :business_type
      t.string :industry
      t.boolean :custom_domain_enabled, default: false
      t.boolean :ssl_enabled, default: false
      t.datetime :subscription_ends_at
      t.string :subscription_status, default: 'trial'

      t.timestamps
    end

    add_index :companies, :subdomain, unique: true
    add_index :companies, :domain, unique: true
    add_index :companies, :active
  end
end
