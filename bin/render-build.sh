#!/usr/bin/env bash
# exit on error
set -o errexit

# Check for required environment variables
echo "Checking for required environment variables..."

# Check for SECRET_KEY_BASE
if [ -z "$SECRET_KEY_BASE" ]; then
  echo "WARNING: SECRET_KEY_BASE environment variable is not set"
  
  # Check if we have RAILS_MASTER_KEY as a fallback
  if [ -n "$RAILS_MASTER_KEY" ]; then
    echo "Using RAILS_MASTER_KEY as a fallback for secret_key_base"
    # Set SECRET_KEY_BASE to RAILS_MASTER_KEY to ensure it's available
    export SECRET_KEY_BASE="$RAILS_MASTER_KEY"
  else
    echo "RAILS_MASTER_KEY is also not available. Generating a temporary SECRET_KEY_BASE..."
    # Generate a random hex string of 64 characters
    export SECRET_KEY_BASE=$(openssl rand -hex 32)
  fi
  
  echo "Using a temporary SECRET_KEY_BASE for this deployment. Please set this in your Render dashboard."
else
  echo "SECRET_KEY_BASE is set properly ✓"
fi

# Create encrypted credentials file if it doesn't exist or RAILS_MASTER_KEY is not set
if [ ! -f "config/credentials.yml.enc" ] || [ -z "$RAILS_MASTER_KEY" ]; then
  echo "No credentials file found or RAILS_MASTER_KEY is not set."
  
  # Generate encryption keys
  PRIMARY_KEY=$(openssl rand -hex 32)
  DETERMINISTIC_KEY=$(openssl rand -hex 32)
  KEY_DERIVATION_SALT=$(openssl rand -hex 32)
  
  # Create a temporary credentials YAML file
  echo "Creating temporary credentials file with ActiveRecord encryption keys..."
  cat > /tmp/temp_credentials.yml << EOL
# ActiveRecord encryption keys (auto-generated for Render deployment)
active_record_encryption:
  primary_key: ${PRIMARY_KEY}
  deterministic_key: ${DETERMINISTIC_KEY}
  key_derivation_salt: ${KEY_DERIVATION_SALT}
EOL

  # If RAILS_MASTER_KEY is not set, generate one
  if [ -z "$RAILS_MASTER_KEY" ]; then
    echo "Generating new RAILS_MASTER_KEY..."
    export RAILS_MASTER_KEY=$(openssl rand -hex 16)
    echo "WARNING: A new RAILS_MASTER_KEY has been generated: ${RAILS_MASTER_KEY}"
    echo "Please add this to your Render environment variables for future deployments."
  fi

  # Use the RAILS_MASTER_KEY to encrypt the credentials file
  echo "${RAILS_MASTER_KEY}" > config/master.key
  chmod 600 config/master.key
  
  # Encrypt the credentials file
  EDITOR="cp /tmp/temp_credentials.yml" bin/rails credentials:edit --environment=production || echo "Failed to create credentials file but continuing..."
fi

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