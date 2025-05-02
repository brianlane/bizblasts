class CreateTaxRatesAgain < ActiveRecord::Migration[8.0]
  def change
    create_table :tax_rates do |t|
      t.string :name, null: false
      t.decimal :rate, precision: 10, scale: 4, null: false # Store rate as decimal (e.g., 0.08 for 8%)
      t.string :region # Optional: For region-specific taxes
      t.boolean :applies_to_shipping, default: false
      t.references :business, null: false, foreign_key: true

      t.timestamps
    end
    add_index :tax_rates, [:name, :business_id], unique: true
    # add_index :tax_rates, [:region, :business_id] # Index if frequently querying by region
  end
end
