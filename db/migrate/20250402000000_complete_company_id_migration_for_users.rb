class CompleteCompanyIdMigrationForUsers < ActiveRecord::Migration[8.0]
  def change
    # This migration is now a fallback in case the initial migration fails
    # It checks if company_id exists, and if not, runs the necessary steps
    
    # Only run if company_id doesn't exist yet
    unless column_exists?(:users, :company_id)
      # Add the column as nullable
      add_reference :users, :company, null: true, foreign_key: true, index: true
      
      # Populate with default tenant
      reversible do |dir|
        dir.up do
          default_company = Company.find_by(subdomain: 'default')
          if default_company
            execute <<-SQL
              UPDATE users SET company_id = #{default_company.id}
              WHERE company_id IS NULL
            SQL
          end
        end
      end
      
      # Make it required
      change_column_null :users, :company_id, false
    end
  end
end 