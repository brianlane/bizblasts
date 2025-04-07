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
fi

# Create a basic CSS file if it doesn't exist or is empty
if [ ! -s "app/assets/builds/active_admin.css" ]; then
  echo "Creating basic fallback ActiveAdmin CSS file..."
  cat > app/assets/builds/active_admin.css << 'EOL'
/* Fallback ActiveAdmin CSS */
body.active_admin {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen-Sans, Ubuntu, Cantarell, "Helvetica Neue", sans-serif;
  line-height: 1.5;
  font-size: 14px;
  color: #333;
  background: #f4f4f4;
  margin: 0;
  padding: 0;
}

#header {
  background: #5E6469;
  color: white;
  padding: 10px 20px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
}

#header h1 {
  font-weight: normal;
  margin: 0;
}

#header a, #header a:link, #header a:visited {
  color: white;
  text-decoration: none;
}

body.logged_out {
  background: #f8f8f8;
  padding-top: 50px;
}

#login {
  max-width: 400px;
  margin: 0 auto;
  background: white;
  padding: 30px;
  border-radius: 5px;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
}

#login h2 {
  margin-top: 0;
  text-align: center;
  color: #5E6469;
}

.flash {
  padding: 10px 15px;
  margin-bottom: 20px;
  border-radius: 3px;
}

.flash.notice {
  background: #dff0d8;
  color: #3c763d;
}

.flash.error {
  background: #f2dede;
  color: #a94442;
}
EOL
fi

# Compile the CSS
bundle exec rails assets:precompile
bundle exec rails assets:clean

# Force ActiveAdmin CSS to public/assets 
echo "Ensuring assets are available in public/assets..."
mkdir -p public/assets

# Copy ActiveAdmin CSS
cp app/assets/builds/active_admin.css public/assets/

# Generate MD5 hash for ActiveAdmin CSS
if command -v md5sum > /dev/null; then
  # Linux
  AA_MD5=$(md5sum "app/assets/builds/active_admin.css" | cut -d' ' -f1)
else
  # macOS
  AA_MD5=$(md5 -q "app/assets/builds/active_admin.css")
fi

# Create a digested version for cache busting
cp app/assets/builds/active_admin.css "public/assets/active_admin-${AA_MD5}.css"
echo "ActiveAdmin assets copied successfully ✓"

# Ensure application.css exists
if [ ! -f "app/assets/builds/application.css" ] || [ ! -s "app/assets/builds/application.css" ]; then
  echo "Creating basic application.css file..."
  echo "/* Basic application styles */" > app/assets/builds/application.css
fi

# Copy application CSS and generate digested version
cp app/assets/builds/application.css public/assets/
if command -v md5sum > /dev/null; then
  # Linux
  APP_CSS_MD5=$(md5sum "app/assets/builds/application.css" | cut -d' ' -f1)
else
  # macOS
  APP_CSS_MD5=$(md5 -q "app/assets/builds/application.css")
fi
cp app/assets/builds/application.css "public/assets/application-${APP_CSS_MD5}.css"
echo "Application CSS copied successfully ✓"

# Ensure application.js exists
if [ ! -f "app/assets/builds/application.js" ]; then
  echo "Creating basic application.js file..."
  echo "/* Basic application JavaScript */" > app/assets/builds/application.js
fi

# Copy application JS and generate digested version
cp app/assets/builds/application.js public/assets/
if command -v md5sum > /dev/null; then
  # Linux
  APP_JS_MD5=$(md5sum "app/assets/builds/application.js" | cut -d' ' -f1)
else
  # macOS
  APP_JS_MD5=$(md5 -q "app/assets/builds/application.js")
fi
cp app/assets/builds/application.js "public/assets/application-${APP_JS_MD5}.js"
echo "Application JS copied successfully ✓"

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