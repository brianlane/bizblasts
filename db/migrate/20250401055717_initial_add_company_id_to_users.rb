class InitialAddCompanyIdToUsers < ActiveRecord::Migration[8.0]
  def change
    # First add the column as nullable
    add_reference :users, :company, null: true, foreign_key: true
    
    # Then populate existing users with a default company
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
    
    # Finally make it non-nullable after data is migrated
    change_column_null :users, :company_id, false
  end
end
