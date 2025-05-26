# Tailwind CSS CI Build Fix

## Problem

The GitHub Actions CI was failing when trying to build Tailwind CSS with the error:

```
ActiveRecord::ConnectionNotEstablished: connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed: No such file or directory
```

This occurred because:

1. The `bundle exec rails tailwindcss:build` command loads the full Rails environment
2. The Rails environment loads all initializers, including `config/initializers/solid_queue.rb`
3. The SolidQueue initializer tries to create/find database records during initialization
4. The database wasn't available yet when building Tailwind CSS

## Solution

We implemented a multi-layered solution:

### 1. Smart SolidQueue Initializer

Modified `config/initializers/solid_queue.rb` to:
- Skip setup during asset compilation (`RAILS_DISABLE_ASSET_COMPILATION=true`)
- Skip setup when explicitly disabled (`SKIP_SOLID_QUEUE_SETUP=true`)
- Test database connectivity before attempting operations
- Gracefully handle database connection errors
- Check for required tables before proceeding

### 2. Standalone Tailwind Build Script

Created `bin/build-tailwind-standalone.sh` that:
- Sets environment variables to skip database operations
- Tries multiple approaches to build Tailwind CSS:
  1. Standalone `tailwindcss` binary
  2. Bundled `tailwindcss` command
  3. Custom Rake task as fallback

### 3. Custom Rake Task

Created `lib/tasks/tailwind_standalone.rake` with `tailwind:build_standalone` task that:
- Builds Tailwind CSS without requiring Rails environment
- Uses the `tailwindcss-rails` gem's executable directly
- Has multiple fallback strategies
- Provides detailed logging and error handling

### 4. Updated CI Workflow

Modified `.github/workflows/ci.yml` to:
- Test Tailwind build early (before database setup)
- Build Tailwind CSS after database is ready (as backup)
- Use proper environment variables to skip database operations

### 5. Improved Test Environment

Updated `config/environments/test.rb` to:
- Conditionally disable asset handling based on environment variables
- Allow asset builds when needed while keeping tests fast

## Usage

### In Development
```bash
# Use the normal Rails command (requires database)
bundle exec rails tailwindcss:build

# Or use the standalone version (no database required)
./bin/build-tailwind-standalone.sh
```

### In CI/Production
```bash
# Set environment variables and use standalone build
export RAILS_DISABLE_ASSET_COMPILATION=true
export SKIP_SOLID_QUEUE_SETUP=true
export DISABLE_DATABASE_ENVIRONMENT_CHECK=1
./bin/build-tailwind-standalone.sh
```

### Testing the Fix
```bash
# Run the test script to verify everything works
./script/test_tailwind_build.rb
```

## Environment Variables

- `RAILS_DISABLE_ASSET_COMPILATION=true` - Skips asset-related operations in initializers
- `SKIP_SOLID_QUEUE_SETUP=true` - Specifically skips SolidQueue initialization
- `DISABLE_DATABASE_ENVIRONMENT_CHECK=1` - Disables database environment checks

## Files Modified

1. `config/initializers/solid_queue.rb` - Made database-aware
2. `bin/build-tailwind-standalone.sh` - New standalone build script
3. `lib/tasks/tailwind_standalone.rake` - New Rake task
4. `.github/workflows/ci.yml` - Updated CI workflow
5. `config/environments/test.rb` - Conditional asset handling
6. `script/test_tailwind_build.rb` - Test script

## Benefits

1. **Robust**: Multiple fallback strategies ensure builds work in various environments
2. **Fast**: Avoids loading full Rails environment when not needed
3. **Safe**: Graceful error handling prevents CI failures
4. **Flexible**: Works with or without database access
5. **Testable**: Includes comprehensive test script

## Future Considerations

- Monitor for changes in `tailwindcss-rails` gem that might affect the build process
- Consider using a dedicated asset build container in CI for even better isolation
- Evaluate moving to a completely separate asset build pipeline if the application grows significantly 