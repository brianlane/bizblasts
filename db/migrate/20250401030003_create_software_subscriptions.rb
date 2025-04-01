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