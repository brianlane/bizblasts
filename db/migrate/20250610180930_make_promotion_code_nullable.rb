class MakePromotionCodeNullable < ActiveRecord::Migration[8.0]
  def change
    change_column_null :promotions, :code, true
    
    # Update unique constraint to handle NULL codes properly
    remove_index :promotions, [:code, :business_id], if_exists: true
    add_index :promotions, [:code, :business_id], unique: true, where: "code IS NOT NULL"
  end
end
