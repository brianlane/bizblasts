#!/usr/bin/env bash
set -e

echo "Building Tailwind CSS without Rails environment..."

# Set environment variables to skip database-dependent operations
export RAILS_DISABLE_ASSET_COMPILATION=true
export SKIP_SOLID_QUEUE_SETUP=true
export DISABLE_DATABASE_ENVIRONMENT_CHECK=1

# Create builds directory if it doesn't exist
mkdir -p app/assets/builds

# Check if tailwindcss-rails gem provides a standalone binary
if command -v tailwindcss >/dev/null 2>&1; then
    echo "Using standalone tailwindcss binary..."
    tailwindcss -i ./app/assets/tailwind/application.css -o ./app/assets/builds/tailwind.css --minify
elif bundle exec which tailwindcss >/dev/null 2>&1; then
    echo "Using tailwindcss from bundle..."
    bundle exec tailwindcss -i ./app/assets/tailwind/application.css -o ./app/assets/builds/tailwind.css --minify
else
    echo "Attempting to use custom standalone Rake task..."
    # Use our custom Rake task that doesn't require database access
    bundle exec rake tailwind:build_standalone
fi

echo "Tailwind CSS build completed successfully!" 