class FixOrdersStatusCheckConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing check constraint
    execute <<-SQL
      ALTER TABLE orders DROP CONSTRAINT IF EXISTS status_enum_check;
    SQL
    
    # Add the updated check constraint that includes business_deleted
    execute <<-SQL
      ALTER TABLE orders ADD CONSTRAINT status_enum_check 
      CHECK (status IN ('pending_payment', 'paid', 'cancelled', 'shipped', 'refunded', 'processing', 'business_deleted'));
    SQL
  end

  def down
    # Remove the updated check constraint
    execute <<-SQL
      ALTER TABLE orders DROP CONSTRAINT IF EXISTS status_enum_check;
    SQL
    
    # Restore the original check constraint (without business_deleted)
    execute <<-SQL
      ALTER TABLE orders ADD CONSTRAINT status_enum_check 
      CHECK (status IN ('pending_payment', 'paid', 'cancelled', 'shipped', 'refunded', 'processing'));
    SQL
  end
end
