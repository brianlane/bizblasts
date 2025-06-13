class CreateLoyaltyPrograms < ActiveRecord::Migration[8.0]
  def change
    create_table :loyalty_programs do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :points_name, default: 'points', null: false
      t.integer :points_for_booking, default: 0, null: false
      t.integer :points_for_referral, default: 0, null: false
      t.decimal :points_per_dollar, precision: 8, scale: 2, default: 0.0, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    
    add_index :loyalty_programs, :active
  end
end
