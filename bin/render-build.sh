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
# Ensure the public/assets directory exists
mkdir -p public/assets

# Handle ActiveAdmin assets explicitly to ensure they're properly compiled
if [ -f "app/assets/stylesheets/active_admin.scss" ]; then
  echo "Compiling ActiveAdmin assets manually..."
  
  # Install required node packages
  yarn add sass

  # Get ActiveAdmin gem path
  AA_PATH=$(bundle show activeadmin)
  echo "ActiveAdmin Path: $AA_PATH"
  
  # Compile SCSS to CSS with proper load paths
  npx sass app/assets/stylesheets/active_admin.scss:app/assets/builds/active_admin.css \
    --no-source-map \
    --load-path=node_modules \
    --load-path="$AA_PATH/app/assets/stylesheets" || \
  echo "Warning: Failed to compile ActiveAdmin CSS manually, continuing with fallback"
  
  # If compilation failed, create a basic fallback file
  if [ ! -s "app/assets/builds/active_admin.css" ]; then
    echo "Creating fallback ActiveAdmin CSS file..."
    cp app/assets/builds/active_admin.css public/assets/active_admin.css 2>/dev/null || \
    echo "/* Basic ActiveAdmin styles */" > public/assets/active_admin.css
  fi
fi

# Compile the CSS
bundle exec rails assets:precompile
bundle exec rails assets:clean

# Force ActiveAdmin CSS to public/assets 
echo "Ensuring ActiveAdmin assets are available in public assets..."
mkdir -p public/assets

# Try multiple possible source locations
for source in app/assets/builds/active_admin.css app/assets/stylesheets/active_admin.css public/assets/active_admin-*.css; do
  if [ -f "$source" ]; then
    echo "Found ActiveAdmin CSS at $source"
    cp "$source" public/assets/active_admin.css
    
    # Get MD5 hash in a cross-platform way (works on both Linux and macOS)
    if command -v md5sum > /dev/null; then
      # Linux
      MD5=$(md5sum "$source" | cut -d' ' -f1)
    else
      # macOS
      MD5=$(md5 -q "$source")
    fi
    
    cp "$source" "public/assets/active_admin-${MD5}.css"
    echo "ActiveAdmin assets copied successfully ✓"
    break
  fi
done

# If we still don't have the file, create a symbolic link
if [ ! -f "public/assets/active_admin.css" ]; then
  echo "WARNING: ActiveAdmin CSS not found in expected locations, creating alternative..."
  
  # Create a simple CSS file as a fallback
  echo "/* Fallback ActiveAdmin CSS */" > public/assets/active_admin.css
  cp public/assets/active_admin.css public/assets/active_admin-fallback.css
  
  echo "Created fallback ActiveAdmin CSS"
fi

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

# Only load schema for fresh databases, not in production with existing data
if [[ "$RAILS_ENV" != "production" || ! -z "$RESET_DB" ]]; then
  echo "Loading database schema..."
  bundle exec rails db:schema:load || echo "Schema load failed, but continuing..."
else
  echo "Skipping schema load to preserve production data..."
fi

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

# Create admin user from environment variables if configured
if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASSWORD" ]]; then
  echo "Creating admin user from environment variables..."
  bundle exec rails runner "
    admin = AdminUser.find_or_initialize_by(email: '$ADMIN_EMAIL') do |user|
      user.password = '$ADMIN_PASSWORD'
      user.password_confirmation = '$ADMIN_PASSWORD'
    end
    
    if admin.new_record?
      admin.save!
      puts \"Created admin user: $ADMIN_EMAIL with password from environment\"
    else
      puts \"Admin user $ADMIN_EMAIL already exists\"
    end
  "
else
  echo "Skipping admin user creation - environment variables not set"
fi

echo "Build completed successfully!" 