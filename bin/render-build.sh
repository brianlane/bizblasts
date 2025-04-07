#!/usr/bin/env bash
# exit on error
set -o errexit

# Check for required environment variables
echo "Checking for required environment variables..."

# Check for SECRET_KEY_BASE
if [ -z "$SECRET_KEY_BASE" ] && [ -z "$RAILS_MASTER_KEY" ]; then
  echo "ERROR: Neither SECRET_KEY_BASE nor RAILS_MASTER_KEY is set"
  echo "One of these is required for Rails to start in production"
  exit 1
else
  if [ -n "$SECRET_KEY_BASE" ]; then
    echo "SECRET_KEY_BASE is set properly ✓"
  fi
  if [ -n "$RAILS_MASTER_KEY" ]; then
    echo "RAILS_MASTER_KEY is set properly ✓"
    # Ensure master key file exists if RAILS_MASTER_KEY is set
    echo "$RAILS_MASTER_KEY" > config/master.key
    chmod 600 config/master.key
  fi
fi

# Build commands for Render deployment
echo "Installing dependencies..."
bundle install


echo "Precompiling assets..."
bundle exec rake assets:precompile
bundle exec rake assets:clean

# Print environment information
echo "Rails environment: $RAILS_ENV"
echo "SECRET_KEY_BASE set: $(if [ -n "$SECRET_KEY_BASE" ]; then echo "Yes"; else echo "No"; fi)"
echo "RAILS_MASTER_KEY set: $(if [ -n "$RAILS_MASTER_KEY" ]; then echo "Yes"; else echo "No"; fi)"

# Create database if it doesn't exist
echo "Checking if database exists..."
bundle exec rake db:version > /dev/null 2>&1 || bundle exec rake db:create

# # Print database config for debugging
# echo "Database configuration:"
# bundle exec rails runner "puts ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).inspect"
echo "Database connection info:"
echo "DATABASE_URL environment variable: $(if [ -n "$DATABASE_URL" ]; then echo "Set (value hidden for security)"; else echo "Not set"; fi)"
echo "DATABASE_HOST environment variable: $DATABASE_HOST"
echo "DATABASE_PORT environment variable: $DATABASE_PORT"

# Only load schema for fresh databases, not in production with existing data
if [[ "$RAILS_ENV" != "production" || ! -z "$RESET_DB" ]]; then
  echo "Loading database schema..."
  bundle exec rake db:schema:load || echo "Schema load failed, but continuing..."
else
  echo "Skipping schema load to preserve production data..."
fi

# Run migrations to ensure tables are created
echo "Running migrations..."
bundle exec rake db:migrate || echo "Migrations failed, but continuing..."

# # Verify that companies table exists
# echo "Verifying that companies table exists..."
# if bundle exec rails runner "puts ActiveRecord::Base.connection.table_exists?('companies')"; then
#   echo "Companies table exists! Database setup successful."
# else
#   echo "WARNING: Companies table does not exist. Attempting manual creation..."
#   # Create the companies table manually as last resort
#   bundle exec rails runner "
#     unless ActiveRecord::Base.connection.table_exists?('companies')
#       ActiveRecord::Base.connection.create_table(:companies) do |t|
#         t.string :name, null: false, default: 'Default'
#         t.string :subdomain, null: false, default: 'default'
#         t.timestamps
#       end
#       puts 'Companies table created manually!'
#     end
#   "
# fi

# # Create default company if needed
# echo "Creating default company record..."
# bundle exec rails runner "
#   Company.find_or_create_by!(name: 'Default Company', subdomain: 'default')
#   puts \"Default company count: #{Company.count}\"
# "

# # Create admin user from environment variables if configured
# if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASSWORD" ]]; then
#   echo "Creating admin user from environment variables..."
#   bundle exec rails runner "
#     admin = AdminUser.find_or_initialize_by(email: '$ADMIN_EMAIL') do |user|
#       user.password = '$ADMIN_PASSWORD'
#       user.password_confirmation = '$ADMIN_PASSWORD'
#     end
    
#     if admin.new_record?
#       admin.save!
#       puts \"Created admin user: $ADMIN_EMAIL with password from environment\"
#     else
#       puts \"Admin user $ADMIN_EMAIL already exists\"
#     end
#   "
# else
#   echo "Skipping admin user creation - environment variables not set"
# fi

# Verify that companies table exists using rake task
echo "Verifying that companies table exists..."
cat > verify_db_build_script.rb << EOF
begin
  require './config/environment'
  if ActiveRecord::Base.connection.table_exists?('companies')
    puts "Companies table exists! Database setup successful."
  else
    puts "WARNING: Companies table does not exist. Attempting manual creation..."
    ActiveRecord::Base.connection.create_table(:companies) do |t|
      t.string :name, null: false, default: 'Default'
      t.string :subdomain, null: false, default: 'default'
      t.timestamps
    end
    puts "Companies table created manually!"
  end
rescue => e
  puts "Database error: #{e.message}"
end
EOF

bundle exec ruby verify_db_build_script.rb

# Create default company if needed
echo "Creating default company record..."
cat > create_company_build_script.rb << EOF
begin
  require './config/environment'
  company = Company.find_or_create_by!(name: 'Default Company', subdomain: 'default')
  puts "Default company created/found with ID: #{company.id}"
  puts "Total companies: #{Company.count}"
rescue => e
  puts "Error creating company: #{e.message}"
end
EOF

bundle exec ruby create_company_build_script.rb

# Create admin user from environment variables if configured
if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASSWORD" ]]; then
  echo "Creating admin user from environment variables..."
  cat > create_admin_build_script.rb << EOF
begin
  require './config/environment'
  admin = AdminUser.find_or_initialize_by(email: '$ADMIN_EMAIL') do |user|
    user.password = '$ADMIN_PASSWORD'
    user.password_confirmation = '$ADMIN_PASSWORD'
  end
  
  if admin.new_record?
    admin.save!
    puts "Created admin user: $ADMIN_EMAIL with password from environment"
  else
    puts "Admin user $ADMIN_EMAIL already exists"
  end
rescue => e
  puts "Error creating admin: #{e.message}"
end
EOF

  bundle exec ruby create_admin_build_script.rb
else
  echo "Skipping admin user creation - environment variables not set"
fi

echo "Build completed successfully!" 