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

# Remove stale bin/bundle if it exists (can cause issues with Bundler upgrades)
rm -f bin/bundle

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

# Use stable Chrome version for reproducible builds
# Update this periodically by checking: https://googlechromelabs.github.io/chrome-for-testing/
CHROME_VERSION=${CHROME_VERSION:-"131.0.6778.204"}

# SECURITY: Validate Chrome version format to prevent injection
# Only allow numbers and dots (e.g., "131.0.6778.204")
if ! [[ "$CHROME_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: Invalid CHROME_VERSION format: $CHROME_VERSION"
  echo "Expected format: X.Y.Z.W (e.g., 131.0.6778.204)"
  echo "Using default version instead: 131.0.6778.204"
  CHROME_VERSION="131.0.6778.204"
fi

# Chrome for Testing publishes Linux builds as .zip files
CHROME_DOWNLOAD_URL="https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chrome-linux64.zip"
CHROME_INSTALL_DIR="$PWD/vendor/chrome"
CHROME_ARCHIVE_PATH="/tmp/chrome-linux64.zip"
CHROME_ARCHIVE_FAILURE_REASON=""

# Expected SHA256 checksum for this version (verify manually when updating)
# To get checksum: curl -sL <URL> | sha256sum
CHROME_EXPECTED_SHA256=${CHROME_EXPECTED_SHA256:-""}

echo "Chrome version: ${CHROME_VERSION}"
echo "Download URL: ${CHROME_DOWNLOAD_URL}"
echo "Install directory: ${CHROME_INSTALL_DIR}"
echo "Current working directory: ${PWD}"

# Clean up old installation
if [ -d "$CHROME_INSTALL_DIR" ]; then
  echo "Removing old Chrome installation..."
  rm -rf "$CHROME_INSTALL_DIR"
fi
mkdir -p "$CHROME_INSTALL_DIR"

# Download Chrome archive
echo "Downloading Chrome..."
DOWNLOAD_ATTEMPTS=0
MAX_DOWNLOAD_ATTEMPTS=3
DOWNLOAD_SUCCESS=false

while [ $DOWNLOAD_ATTEMPTS -lt $MAX_DOWNLOAD_ATTEMPTS ] && [ "$DOWNLOAD_SUCCESS" = "false" ]; do
  DOWNLOAD_ATTEMPTS=$((DOWNLOAD_ATTEMPTS + 1))
  echo "Download attempt ${DOWNLOAD_ATTEMPTS}/${MAX_DOWNLOAD_ATTEMPTS}..."

  if curl -fsSL --retry 2 --retry-delay 5 --connect-timeout 30 --max-time 300 \
     "$CHROME_DOWNLOAD_URL" -o "$CHROME_ARCHIVE_PATH"; then
    DOWNLOAD_SUCCESS=true
    echo "✓ Chrome downloaded successfully"
  else
    echo "✗ Download attempt ${DOWNLOAD_ATTEMPTS} failed"
    if [ $DOWNLOAD_ATTEMPTS -lt $MAX_DOWNLOAD_ATTEMPTS ]; then
      echo "Retrying in 10 seconds..."
      sleep 10
    fi
  fi
done

if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
  echo "ERROR: Failed to download Chrome after ${MAX_DOWNLOAD_ATTEMPTS} attempts"
  echo "URL: ${CHROME_DOWNLOAD_URL}"
  echo "FALLBACK: Attempting to continue without Chrome (manual method will be required)"
  echo "NOTE: You can set CHROME_VERSION environment variable to try a different version"
  # Don't exit - allow build to continue for manual Place ID entry
else
  # Verify checksum if provided (recommended for production)
  if [ -n "$CHROME_EXPECTED_SHA256" ]; then
    echo "Verifying Chrome checksum..."
    ACTUAL_SHA256=$(sha256sum "$CHROME_ARCHIVE_PATH" | awk '{print $1}')
    if [ "$ACTUAL_SHA256" != "$CHROME_EXPECTED_SHA256" ]; then
      echo "ERROR: Chrome checksum mismatch!"
      echo "  Expected: ${CHROME_EXPECTED_SHA256}"
      echo "  Actual:   ${ACTUAL_SHA256}"
      echo "SECURITY WARNING: Checksum verification failed. Not installing Chrome."
      rm -f "$CHROME_ARCHIVE_PATH"
      CHROME_ARCHIVE_FAILURE_REASON="Chrome download succeeded, but checksum verification failed. Archive removed for safety."
      echo "FALLBACK: Continuing without Chrome (manual method will be required)"
    else
      echo "Chrome checksum verified ✓"
    fi
  else
    echo "WARNING: No checksum provided - skipping verification (set CHROME_EXPECTED_SHA256)"
  fi

  # Install Chrome if download was successful and checksum passed (or skipped)
  if [ -f "$CHROME_ARCHIVE_PATH" ]; then
    echo "Extracting Chrome..."
    echo "Archive size: $(du -h "$CHROME_ARCHIVE_PATH" | cut -f1)"

    # Check if unzip is available
    if ! command -v unzip &> /dev/null; then
      echo "✗ ERROR: unzip command not found. Installing unzip..."
      # Try to install unzip if possible
      if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y unzip || echo "Failed to install unzip"
      else
        echo "Cannot install unzip automatically. Chrome installation will fail."
      fi
    fi

    mkdir -p /tmp/chrome-download
    if unzip -q "$CHROME_ARCHIVE_PATH" -d /tmp/chrome-download 2>&1; then
      echo "✓ Chrome archive extracted successfully"

      # Check what was extracted
      echo "Extracted contents:"
      ls -la /tmp/chrome-download/

      if [ -d /tmp/chrome-download/chrome-linux64 ]; then
        echo "✓ Found chrome-linux64 directory"
        mv /tmp/chrome-download/chrome-linux64 "$CHROME_INSTALL_DIR/"
        chmod +x "$CHROME_INSTALL_DIR/chrome-linux64/chrome"
        echo "✓ Chrome moved to: $CHROME_INSTALL_DIR/chrome-linux64/"
      else
        echo "✗ ERROR: chrome-linux64 directory not found after extraction"
        echo "Directory contents:"
        ls -la /tmp/chrome-download/
      fi
    else
      echo "✗ ERROR: Failed to extract Chrome archive"
      echo "Make sure unzip is installed and the archive is valid"
    fi

    rm -rf /tmp/chrome-download "$CHROME_ARCHIVE_PATH"

    # Verify Chrome installation
    echo "Verifying Chrome installation..."
    CHROME_BINARY="$CHROME_INSTALL_DIR/chrome-linux64/chrome"

    if [ -f "$CHROME_BINARY" ]; then
      echo "✓ Chrome binary exists at: $CHROME_BINARY"

      # Check file permissions
      CHROME_PERMS=$(stat -c "%a" "$CHROME_BINARY" 2>/dev/null || stat -f "%Lp" "$CHROME_BINARY" 2>/dev/null)
      echo "  File permissions: $CHROME_PERMS"

      # Make extra sure it's executable
      chmod +x "$CHROME_BINARY"

      # Test if Chrome can actually run (not just exist)
      echo "Testing if Chrome can execute..."
      CHROME_VERSION_OUTPUT=$("$CHROME_BINARY" --version 2>&1 || echo "FAILED_TO_EXECUTE")

      if echo "$CHROME_VERSION_OUTPUT" | grep -qi "Chrome"; then
        echo "✓ Chrome installation verified successfully"
        echo "✓ Chrome version: $CHROME_VERSION_OUTPUT"

        # Set absolute path for Render environment
        ABSOLUTE_CHROME_PATH=$(cd "$(dirname "$CHROME_BINARY")" && pwd)/$(basename "$CHROME_BINARY")
        echo "✓ Absolute Chrome path: $ABSOLUTE_CHROME_PATH"
        echo "  (This should match CUPRITE_BROWSER_PATH environment variable)"
      else
        echo "✗ ERROR: Chrome binary exists but cannot execute"
        echo "✗ Chrome version check output: $CHROME_VERSION_OUTPUT"
        echo "✗ This usually means missing system dependencies"

        # Try to diagnose the issue
        echo "Diagnosing Chrome dependencies..."
        if command -v ldd &> /dev/null; then
          MISSING_LIBS=$(ldd "$CHROME_BINARY" 2>&1 | grep "not found" || echo "")
          if [ -n "$MISSING_LIBS" ]; then
            echo "Missing libraries:"
            echo "$MISSING_LIBS"
          else
            echo "All shared libraries found (according to ldd)"
          fi
        fi

        echo "WARNING: Place ID extraction may not work. Chrome cannot start."
        echo "Check that render.yaml includes all required system packages."
      fi
    else
      echo "✗ ERROR: Chrome executable not found after installation at: $CHROME_BINARY"
      echo "Expected location: $CHROME_BINARY"

      # Debug: show what's in the install directory
      if [ -d "$CHROME_INSTALL_DIR" ]; then
        echo "Chrome install directory contents:"
        find "$CHROME_INSTALL_DIR" -type f -name "chrome*" 2>/dev/null || echo "No chrome files found"
        echo "Full directory tree:"
        ls -laR "$CHROME_INSTALL_DIR" | head -50
      else
        echo "Install directory doesn't exist: $CHROME_INSTALL_DIR"
      fi
    fi
  else
    echo "✗ ERROR: Chrome archive file not available at $CHROME_ARCHIVE_PATH"
    if [ -n "$CHROME_ARCHIVE_FAILURE_REASON" ]; then
      echo "$CHROME_ARCHIVE_FAILURE_REASON"
    else
      echo "This usually indicates the download failed but was not caught by error handling"
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
