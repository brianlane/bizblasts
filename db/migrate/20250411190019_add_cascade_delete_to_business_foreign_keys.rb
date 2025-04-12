class AddCascadeDeleteToBusinessForeignKeys < ActiveRecord::Migration[8.0]
  def change
    # List of tables and their foreign key names referencing businesses.id
    # Extracted from `rails dbconsole` -> `\\d businesses` output
    foreign_keys = {
      promotions: "fk_rails_0dc1323625",
      services: "fk_rails_4a2cffba54",
      bookings: "fk_rails_6b29963c5c",
      client_businesses: "fk_rails_6f74fc1bf5",
      staff_members: "fk_rails_74b8e82da5",
      pages: "fk_rails_787e898089",
      marketing_campaigns: "fk_rails_7a8451dfa5",
      invoices: "fk_rails_830b37ed59",
      tenant_customers: "fk_rails_97f416f819",
      users: "fk_rails_ffa8fa13ef"
    }

    foreign_keys.each do |table, fk_name|
      # Remove the existing foreign key constraint
      remove_foreign_key table, :businesses, name: fk_name

      # Add the foreign key constraint back with ON DELETE CASCADE
      add_foreign_key table, :businesses, column: :business_id, on_delete: :cascade
    end

    # Handle service_template_id on businesses table itself
    # It references service_templates, not the other way around.
    # If a ServiceTemplate is deleted, we might want to set business.service_template_id to NULL.
    # remove_foreign_key :businesses, :service_templates, name: "fk_rails_9177eafbaf" # Original FK name
    # add_foreign_key :businesses, :service_templates, column: :service_template_id, on_delete: :nullify
    # Decided against modifying service_template FK for now, as it\'s not directly related to business deletion.
  end
end
