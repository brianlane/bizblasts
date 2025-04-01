#!/usr/bin/env bash
# exit on error
set -o errexit

# Build commands for Render deployment
echo "Installing dependencies..."
bundle install

echo "Precompiling assets..."
bundle exec rails assets:precompile
bundle exec rails assets:clean

# Print environment information
echo "Rails environment: $RAILS_ENV"
echo "SECRET_KEY_BASE set: $(if [ -n "$SECRET_KEY_BASE" ]; then echo "Yes"; else echo "No"; fi)"
echo "RAILS_MASTER_KEY set: $(if [ -n "$RAILS_MASTER_KEY" ]; then echo "Yes"; else echo "No"; fi)"

# Print database config for debugging
echo "Database configuration:"
bundle exec rails runner "puts ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).inspect"

# Create database if it doesn't exist
echo "Checking if database exists..."
bundle exec rails db:version > /dev/null 2>&1 || bundle exec rails db:create

# Load schema first, then run migrations
echo "Loading database schema..."
bundle exec rails db:schema:load || echo "Schema load failed, but continuing..."

# Run migrations to ensure tables are created
echo "Running migrations..."
bundle exec rails db:migrate || echo "Migrations failed, but continuing..."

# Verify that companies table exists
echo "Verifying that companies table exists..."
if bundle exec rails runner "puts ActiveRecord::Base.connection.table_exists?('companies')"; then
  echo "Companies table exists! Database setup successful."
else
  echo "WARNING: Companies table does not exist. Attempting manual creation..."
  # Create the companies table manually as last resort
  bundle exec rails runner "
    unless ActiveRecord::Base.connection.table_exists?('companies')
      ActiveRecord::Base.connection.create_table(:companies) do |t|
        t.string :name, null: false, default: 'Default'
        t.string :subdomain, null: false, default: 'default'
        t.timestamps
      end
      puts 'Companies table created manually!'
    end
  "
fi

# Create default company if needed
echo "Creating default company record..."
bundle exec rails runner "
  Company.find_or_create_by!(name: 'Default Company', subdomain: 'default')
  puts \"Default company count: #{Company.count}\"
"

echo "Build completed successfully!" 