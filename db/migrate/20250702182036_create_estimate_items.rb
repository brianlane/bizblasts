class CreateEstimateItems < ActiveRecord::Migration[8.0]
  def change
    create_table :estimate_items do |t|
      t.references :estimate, null: false, foreign_key: true
      t.references :service, null: true, foreign_key: true
      t.string :description
      t.integer :qty
      t.decimal :cost_rate, precision: 10, scale: 2
      t.decimal :tax_rate, precision: 10, scale: 2
      t.decimal :total, precision: 10, scale: 2

      t.timestamps
    end
  end
end
