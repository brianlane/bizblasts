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
