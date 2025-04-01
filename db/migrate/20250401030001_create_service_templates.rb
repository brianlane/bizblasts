class CreateServiceTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :service_templates do |t|
      t.string :name, null: false
      t.text :description
      t.string :category
      t.string :industry
      t.boolean :active, default: true
      t.jsonb :features, default: []
      t.jsonb :pricing, default: {}
      t.jsonb :content, default: {}
      t.jsonb :settings, default: {}
      t.string :status, default: 'draft'
      t.datetime :published_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :service_templates, :active
    add_index :service_templates, :category
    add_index :service_templates, :industry
    add_index :service_templates, :status
  end
end

class CreateClientWebsites < ActiveRecord::Migration[8.0]
  def change
    create_table :client_websites do |t|
      t.references :company, null: false, foreign_key: true
      t.references :service_template, null: false, foreign_key: true
      t.string :name, null: false
      t.string :subdomain
      t.string :domain
      t.boolean :active, default: true
      t.jsonb :content, default: {}
      t.jsonb :settings, default: {}
      t.jsonb :theme, default: {}
      t.string :status, default: 'draft'
      t.datetime :published_at
      t.boolean :custom_domain_enabled, default: false
      t.boolean :ssl_enabled, default: false
      t.jsonb :seo_settings, default: {}
      t.jsonb :analytics, default: {}
      t.text :notes

      t.timestamps
    end

    add_index :client_websites, [:company_id, :subdomain], unique: true
    add_index :client_websites, :domain, unique: true
    add_index :client_websites, :active
    add_index :client_websites, :status
  end
end 