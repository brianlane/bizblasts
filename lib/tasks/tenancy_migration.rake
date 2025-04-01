namespace :tenancy do
  desc "Migrate data from Apartment schemas to acts_as_tenant"
  task migrate_from_apartment: :environment do
    # This task assumes:
    # 1. You have both gems installed during the migration
    # 2. You've already run the migration to add company_id to your tenant models

    # Get all companies
    companies = Company.all

    if companies.empty?
      puts "No companies found. Please make sure you have companies in your database."
      exit
    end

    companies.each do |company|
      puts "Processing tenant: #{company.name} (#{company.subdomain})"

      # Try to switch to the tenant schema
      begin
        require "apartment"
        Apartment::Tenant.switch(company.subdomain) do
          # Migrate User data
          puts "Migrating users..."
          # This assumes User model exists in both schemas
          users = User.unscoped.all
          users.each do |user|
            # Create a new user in the public schema with tenant_id
            new_user = User.unscoped.new(
              email: user.email,
              encrypted_password: user.encrypted_password,
              reset_password_token: user.reset_password_token,
              reset_password_sent_at: user.reset_password_sent_at,
              remember_created_at: user.remember_created_at,
              company_id: company.id,
              created_at: user.created_at,
              updated_at: user.updated_at
            )
            # Use unscoped to avoid tenant filtering
            new_user.save(validate: false)
            puts "  Migrated user: #{user.email}"
          end

          # Add similar blocks for other models that need migration
          # ...
        end
      rescue => e
        puts "Error processing tenant #{company.subdomain}: #{e.message}"
        puts "This tenant may not have a schema or the data has already been migrated."
      end
    end

    puts "Migration completed!"
    puts "Next steps:"
    puts "1. Run migrations to make company_id required on all tenant models"
    puts "2. Remove the Apartment gem from your Gemfile"
    puts "3. Update your views and controllers to use ActsAsTenant"
  end
end
