class CreateLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :locations do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name
      t.string :address
      t.string :city
      t.string :state
      t.string :zip
      t.jsonb :hours

      t.timestamps
    end
  end
end
