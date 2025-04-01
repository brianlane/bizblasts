class CreateSoftwareProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :software_products do |t|
      t.string :name, null: false
      t.text :description
      t.string :version
      t.string :category
      t.boolean :active, default: true
      t.jsonb :features, default: []
      t.jsonb :pricing, default: {}
      t.string :license_type
      t.text :setup_instructions
      t.string :documentation_url
      t.string :support_url
      t.boolean :requires_installation, default: false
      t.boolean :is_saas, default: true
      t.string :status, default: 'draft'
      t.datetime :published_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :software_products, :active
    add_index :software_products, :category
    add_index :software_products, :status
  end
end

class CreateSoftwareSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :software_subscriptions do |t|
      t.references :company, null: false, foreign_key: true
      t.references :software_product, null: false, foreign_key: true
      t.string :status, default: 'active'
      t.datetime :started_at
      t.datetime :ends_at
      t.string :license_key
      t.string :subscription_type
      t.jsonb :subscription_details, default: {}
      t.boolean :auto_renew, default: true
      t.string :payment_status
      t.string :stripe_subscription_id
      t.string :stripe_customer_id
      t.jsonb :usage_metrics, default: {}
      t.text :notes

      t.timestamps
    end

    add_index :software_subscriptions, [:company_id, :software_product_id], unique: true
    add_index :software_subscriptions, :status
    add_index :software_subscriptions, :license_key, unique: true
  end
end 