class AddFeeFieldsToTips < ActiveRecord::Migration[8.0]
  def change
    add_column :tips, :stripe_fee_amount, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :tips, :platform_fee_amount, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :tips, :business_amount, :decimal, precision: 10, scale: 2, null: false
    
    # Add indexes for fee tracking
    add_index :tips, :stripe_fee_amount
    add_index :tips, :platform_fee_amount
    add_index :tips, :business_amount
    
    # Update existing tips to calculate business_amount (amount - fees)
    # Since existing tips have no fees, business_amount = amount
    reversible do |dir|
      dir.up do
        execute "UPDATE tips SET business_amount = amount WHERE business_amount IS NULL"
      end
    end
  end
end
