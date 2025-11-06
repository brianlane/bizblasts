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

# Install system dependencies for headless Chrome
echo "Installing system dependencies for Chrome..."
echo "Note: If you see 'Permission denied' or 'apt-get not found', ensure render.yaml has the packages list configured."
echo "Attempting to use Render's native package manager first..."

# On Render, packages should be installed via render.yaml, but we'll verify and attempt fallback
if command -v apt-get &> /dev/null; then
  echo "apt-get is available, checking if we can use it..."

  # Try without sudo first (Render build environment may not need it)
  if apt-get update -qq 2>/dev/null; then
    echo "Installing Chrome dependencies via apt-get..."
    apt-get install -y \
      libnss3 \
      libatk-bridge2.0-0 \
      libgbm1 \
      libxkbcommon0 \
      libgtk-3-0 \
      libglib2.0-0 \
      libasound2 \
      libdrm2 \
      libxcomposite1 \
      libxdamage1 \
      libxfixes3 \
      libxrandr2 \
      libcups2 \
      libpango-1.0-0 \
      libcairo2 \
      fonts-liberation \
      libx11-xcb1 \
      libxcb-dri3-0 \
      libxtst6 \
      libxss1 \
      2>/dev/null || echo "Warning: Some packages failed to install via apt-get"

    echo "✓ Chrome dependencies installation completed"
  else
    echo "Cannot run apt-get (no permission or not available)"
    echo "Relying on render.yaml packages configuration..."
  fi
else
  echo "apt-get not available, relying on render.yaml packages configuration..."
fi

# Verify critical libraries are present
echo "Checking for critical Chrome dependencies..."
for lib in libnss3.so libgbm.so libgtk-3.so; do
  if ldconfig -p 2>/dev/null | grep -q "$lib"; then
    echo "  ✓ $lib found"
  else
    echo "  ✗ $lib NOT found (Chrome may not work)"
  fi
done

# Install headless Chrome for Cuprite/Ferrum automation
echo "Fetching headless Chrome (chrome-for-testing)..."

# Use pinned Chrome version for reproducible builds (update periodically)
CHROME_VERSION=${CHROME_VERSION:-"132.0.6834.83"}
CHROME_DOWNLOAD_URL="https://storage.googleapis.com/chrome-for-testing/${CHROME_VERSION}/linux64/chrome-linux64.tar.xz"
CHROME_INSTALL_DIR="$PWD/vendor/chrome"

# Expected SHA256 checksum for this version (verify manually when updating)
# To get checksum: curl -sL <URL> | sha256sum
CHROME_EXPECTED_SHA256=${CHROME_EXPECTED_SHA256:-""}

echo "Chrome version: ${CHROME_VERSION}"
echo "Download URL: ${CHROME_DOWNLOAD_URL}"

rm -rf "$CHROME_INSTALL_DIR"
mkdir -p "$CHROME_INSTALL_DIR"

# Download Chrome archive
echo "Downloading Chrome..."
if ! curl -fsSL "$CHROME_DOWNLOAD_URL" -o /tmp/chrome-linux64.tar.xz; then
  echo "ERROR: Failed to download Chrome from ${CHROME_DOWNLOAD_URL}"
  echo "FALLBACK: Attempting to continue without Chrome (manual method will be required)"
  # Don't exit - allow build to continue for manual Place ID entry
else
  # Verify checksum if provided (recommended for production)
  if [ -n "$CHROME_EXPECTED_SHA256" ]; then
    echo "Verifying Chrome checksum..."
    ACTUAL_SHA256=$(sha256sum /tmp/chrome-linux64.tar.xz | awk '{print $1}')
    if [ "$ACTUAL_SHA256" != "$CHROME_EXPECTED_SHA256" ]; then
      echo "ERROR: Chrome checksum mismatch!"
      echo "  Expected: ${CHROME_EXPECTED_SHA256}"
      echo "  Actual:   ${ACTUAL_SHA256}"
      echo "SECURITY WARNING: Checksum verification failed. Not installing Chrome."
      rm -f /tmp/chrome-linux64.tar.xz
      echo "FALLBACK: Continuing without Chrome (manual method will be required)"
    else
      echo "Chrome checksum verified ✓"
    fi
  else
    echo "WARNING: No checksum provided - skipping verification (set CHROME_EXPECTED_SHA256)"
  fi

  # Install Chrome if download was successful and checksum passed (or skipped)
  if [ -f /tmp/chrome-linux64.tar.xz ]; then
    echo "Extracting Chrome..."
    mkdir -p /tmp/chrome-download
    tar -xf /tmp/chrome-linux64.tar.xz -C /tmp/chrome-download
    mv /tmp/chrome-download/chrome-linux64 "$CHROME_INSTALL_DIR"
    chmod +x "$CHROME_INSTALL_DIR/chrome-linux64/chrome"
    rm -rf /tmp/chrome-download /tmp/chrome-linux64.tar.xz

    # Verify Chrome installation
    echo "Verifying Chrome installation..."
    if [ -f "$CHROME_INSTALL_DIR/chrome-linux64/chrome" ]; then
      echo "Chrome binary exists at: $CHROME_INSTALL_DIR/chrome-linux64/chrome"

      # Test if Chrome can actually run (not just exist)
      echo "Testing if Chrome can execute..."
      CHROME_VERSION_OUTPUT=$("$CHROME_INSTALL_DIR/chrome-linux64/chrome" --version 2>&1 || echo "FAILED_TO_EXECUTE")

      if echo "$CHROME_VERSION_OUTPUT" | grep -q "Chrome"; then
        echo "✓ Chrome installation verified successfully"
        echo "✓ Chrome version: $CHROME_VERSION_OUTPUT"
      else
        echo "✗ ERROR: Chrome binary exists but cannot execute"
        echo "✗ Chrome version check output: $CHROME_VERSION_OUTPUT"
        echo "✗ This usually means missing system dependencies"

        # Try to diagnose the issue
        echo "Diagnosing Chrome dependencies..."
        ldd "$CHROME_INSTALL_DIR/chrome-linux64/chrome" 2>&1 | grep "not found" || echo "All shared libraries found"

        echo "WARNING: Place ID extraction may not work. Chrome cannot start."
      fi
    else
      echo "✗ ERROR: Chrome executable not found after installation at: $CHROME_INSTALL_DIR/chrome-linux64/chrome"
      echo "Directory contents:"
      ls -la "$CHROME_INSTALL_DIR" || echo "Install directory doesn't exist"
    fi
  fi
fi

# Install Bun for JavaScript bundling
echo "Installing Bun..."
curl -fsSL https://bun.sh/install | bash
export PATH="$HOME/.bun/bin:$PATH"

# Install JS dependencies (production only)
echo "Installing JavaScript dependencies..."
if command -v yarn &> /dev/null; then
  yarn install --production
else
  npm install --production
fi

# Build ActiveAdmin CSS
echo "Building ActiveAdmin CSS..."
bin/sass-build-activeadmin.sh

# Build Tailwind CSS
echo "Building Tailwind CSS..."
bin/rails tailwindcss:build

# Bundle JavaScript with Bun
echo "Bundling JavaScript..."
bun run build:js

# Precompile assets using Rails/Propshaft
echo "Precompiling assets with Propshaft..."

# Compile the CSS
bundle exec rails assets:precompile
# bundle exec rails assets:clean

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

# Verify that businesses table exists
echo "Verifying that businesses table exists..."
if bundle exec rails runner "puts ActiveRecord::Base.connection.table_exists?('businesses')"; then
  echo "Businesses table exists! Database setup successful."
else
  echo "WARNING: Businesses table does not exist. Attempting manual creation..."
  # Create the businesses table manually as last resort
  bundle exec rails runner "
    unless ActiveRecord::Base.connection.table_exists?('businesses')
      ActiveRecord::Base.connection.create_table(:businesses) do |t|
        t.string :name, null: false, default: 'Default'
        t.string :subdomain, null: false, default: 'default'
        t.timestamps
      end
      puts 'Businesses table created manually!'
    end
  "
fi

# Create default business if needed
echo "Seeding database (default business)..."
bundle exec rails db:seed

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