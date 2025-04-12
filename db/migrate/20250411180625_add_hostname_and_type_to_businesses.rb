class AddHostnameAndTypeToBusinesses < ActiveRecord::Migration[8.0]
  def change
    # Add new columns
    add_column :businesses, :hostname, :string
    add_column :businesses, :host_type, :string # Can store 'subdomain' or 'custom_domain'

    # Backfill data if necessary (optional, depends on existing data)
    # Business.find_each do |business|
    #   if business.subdomain.present?
    #     business.update_columns(hostname: business.subdomain, host_type: 'subdomain')
    #   elsif business.domain.present?
    #     business.update_columns(hostname: business.domain, host_type: 'custom_domain')
    #   end
    # end

    # Remove old columns
    remove_column :businesses, :subdomain, :string
    remove_column :businesses, :domain, :string

    # Add indexes for new columns
    add_index :businesses, :hostname, unique: true
    add_index :businesses, :host_type
  end
end
