class AddCompletedStatusToOrders < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing status constraint
    execute <<-SQL
      ALTER TABLE orders DROP CONSTRAINT IF EXISTS status_enum_check;
    SQL
    
    # Add the updated constraint that includes 'completed'
    execute <<-SQL
      ALTER TABLE orders ADD CONSTRAINT status_enum_check 
      CHECK (status IN ('pending_payment', 'paid', 'cancelled', 'shipped', 'refunded', 'processing', 'completed', 'business_deleted'));
    SQL
  end

  def down
    # Remove the updated constraint
    execute <<-SQL
      ALTER TABLE orders DROP CONSTRAINT IF EXISTS status_enum_check;
    SQL
    
    # Restore the original constraint (without 'completed')
    execute <<-SQL
      ALTER TABLE orders ADD CONSTRAINT status_enum_check 
      CHECK (status IN ('pending_payment', 'paid', 'cancelled', 'shipped', 'refunded', 'processing', 'business_deleted'));
    SQL
  end
end
