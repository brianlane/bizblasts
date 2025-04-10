namespace :data do
  desc "Migrate user data: Convert admin role, link clients via ClientBusiness, nullify client business_id"
  task migrate_users: :environment do
    puts "Starting user data migration..."

    # 1. Convert 'admin' role (0) to 'manager' role (1)
    admin_users = User.where(role: 0) # Assumes old admin role was 0
    if admin_users.any?
      puts "Updating #{admin_users.count} users from role 'admin' (0) to 'manager' (1)..."
      admin_users.update_all(role: 1) # Assumes manager role is 1
      puts "Admin role update complete."
    else
      puts "No users found with role 'admin' (0)."
    end

    # 2. Create ClientBusiness records for existing clients
    client_users_with_business = User.where(role: 3).where.not(business_id: nil) # Assumes client role is 3
    created_count = 0
    skipped_count = 0

    if client_users_with_business.any?
      puts "Found #{client_users_with_business.count} client users with existing business_id. Creating ClientBusiness links..."
      client_users_with_business.find_each do |user|
        # Check if the link already exists (e.g., if task is rerun)
        unless ClientBusiness.exists?(user_id: user.id, business_id: user.business_id)
          begin
            ClientBusiness.create!(user_id: user.id, business_id: user.business_id)
            created_count += 1
          rescue ActiveRecord::RecordInvalid => e
            puts "WARN: Could not create ClientBusiness for User ID: #{user.id}, Business ID: #{user.business_id}. Error: #{e.message}"
            skipped_count += 1
          end
        else
          puts "INFO: ClientBusiness link already exists for User ID: #{user.id}, Business ID: #{user.business_id}. Skipping."
          skipped_count += 1
        end
      end
      puts "Created #{created_count} ClientBusiness links. Skipped #{skipped_count}."
    else
      puts "No client users found with an existing business_id."
    end

    # 3. Nullify business_id for ALL client users
    client_users = User.where(role: 3) # Assumes client role is 3
    if client_users.any?
      puts "Setting business_id to NULL for #{client_users.count} client users..."
      client_users.update_all(business_id: nil)
      puts "Client business_id nullification complete."
    else
      puts "No client users found to nullify business_id."
    end

    puts "User data migration finished."
  end
end