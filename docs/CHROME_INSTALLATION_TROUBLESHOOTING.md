# Chrome Installation Troubleshooting Guide

This guide helps diagnose and fix Chrome installation issues for the Google Place ID extraction feature.

## Problem

The `PlaceIdExtractionJob` is failing with:
```
Chrome/Chromium executable not found. Please check CUPRITE_BROWSER_PATH environment variable or install Chrome.
```

## Root Cause

Chrome is not properly installed in the production environment. This can happen due to:

1. **Download failures** - The Chrome download URL changed or is unavailable
2. **Incorrect Chrome version** - The specified version doesn't exist
3. **Missing environment variable** - `CUPRITE_BROWSER_PATH` is not set correctly
4. **Missing system dependencies** - Required libraries for Chrome are missing
5. **Incorrect file permissions** - Chrome binary is not executable

## Quick Fix Steps

### Step 1: Run Diagnostics

SSH into your Render instance (or use Render Shell) and run:

```bash
bundle exec rails chrome:diagnose
```

This will show:
- ✓ What paths are being checked
- ✓ Whether Chrome was found
- ✓ Whether Chrome can execute
- ✓ What system dependencies are missing

### Step 2: Check Environment Variable

In Render Dashboard, verify that `CUPRITE_BROWSER_PATH` is set:
```
CUPRITE_BROWSER_PATH=/opt/render/project/src/vendor/chrome/chrome-linux64/chrome
```

This should already be in your `render.yaml` file.

### Step 3: Redeploy

The most common fix is to trigger a fresh deployment so Chrome downloads again:

1. Go to Render Dashboard → Your Service
2. Click **"Manual Deploy"** → **"Clear build cache & deploy"**
3. Watch the build logs for Chrome download and installation
4. Look for these messages:
   ```
   ✓ Chrome downloaded successfully
   ✓ Chrome archive extracted successfully
   ✓ Chrome installation verified successfully
   ```

### Step 4: Manual Installation (If Redeploy Fails)

If the redeploy doesn't work, manually install Chrome via Render Shell:

```bash
bundle exec rails chrome:install
```

This will:
- Download Chrome from the official source
- Extract it to `vendor/chrome/chrome-linux64/`
- Set proper permissions
- Test that it can execute

### Step 5: Test Chrome Execution

After installation, test that Chrome can run:

```bash
bundle exec rails chrome:test_execute
```

This should output:
```
✓ Chrome executed successfully!
Version: Chrome/131.0.6778.204
```

## Changes Made to Fix This Issue

### 1. Updated Chrome Download URL

**Old URL (broken):**
```bash
https://storage.googleapis.com/chrome-for-testing/132.0.6834.83/linux64/chrome-linux64.tar.xz
```

**New URL (working):**
```bash
https://storage.googleapis.com/chrome-for-testing-public/131.0.6778.204/linux64/chrome-linux64.tar.gz
```

The old URL used the wrong bucket path and an outdated version.

### 2. Improved Download Reliability

Added:
- ✓ Retry logic (3 attempts with delays)
- ✓ Longer timeout (5 minutes)
- ✓ Better error messages
- ✓ Detailed logging during build

### 3. Better Installation Verification

Added checks for:
- ✓ Archive download success
- ✓ Extraction success
- ✓ File existence
- ✓ File permissions
- ✓ Chrome executable test
- ✓ Missing library detection

### 4. Created Diagnostic Tools

New rake tasks:
- `rails chrome:diagnose` - Full diagnostic report
- `rails chrome:test_execute` - Quick execution test
- `rails chrome:install` - Manual installation

## Files Modified

1. **bin/render-build.sh** - Chrome installation script (lines 83-249)
   - Fixed download URL
   - Added retry logic
   - Improved verification

2. **lib/tasks/chrome_diagnostics.rake** - New diagnostic tools
   - Comprehensive diagnostics
   - Manual installation fallback

3. **render.yaml** - Already has correct config:
   - CUPRITE_BROWSER_PATH environment variable
   - All required system packages

## System Dependencies

Chrome requires these packages (already in `render.yaml`):
- libnss3
- libatk-bridge2.0-0
- libgbm1
- libxkbcommon0
- libgtk-3-0
- libglib2.0-0
- libasound2
- libdrm2
- libxcomposite1
- libxdamage1
- libxfixes3
- libxrandr2
- libcups2
- libpango-1.0-0
- libcairo2
- fonts-liberation

## Verification

After fixing, verify the Place ID extraction works:

1. Log into your application as a business owner
2. Go to Settings → Integrations
3. Paste a Google Maps URL
4. Click "Extract Place ID"
5. Wait 10-15 seconds
6. You should see: "Place ID found: ChIJ..."

## Still Not Working?

If Chrome still doesn't work after following these steps:

1. **Check build logs** - Look for Chrome download errors during deployment
2. **Verify dependencies** - Run `ldd vendor/chrome/chrome-linux64/chrome` to check for missing libraries
3. **Check disk space** - Chrome is ~150MB; ensure enough space
4. **Check Render logs** - Look for job execution errors in application logs
5. **Contact support** - Provide output from `rails chrome:diagnose`

## Production Monitoring

The application has a circuit breaker to prevent excessive failures:

- After 10 consecutive failures, automatic extraction is disabled
- Users are directed to use manual Place ID entry
- Circuit breaker resets when Chrome becomes available
- Monitor with: `Rails.cache.read('place_id_extraction:recent_failures')`

## Manual Place ID Entry (Fallback)

Users can always manually enter Place ID as a fallback:

1. Click "Or enter Place ID manually" link
2. Find Place ID by:
   - Opening Google Maps URL
   - Looking at the URL for `!1s` followed by the Place ID
   - Example: `!1s0x4cfea9cb52fc25db:0xe7d6a4d7bfcef2a!8m2!3d33.5376365`
   - The Place ID is after `!1s`: `0x4cfea9cb52fc25db:0xe7d6a4d7bfcef2a`
3. Paste into form and save

## Testing Locally

To test Chrome installation locally:

```bash
# Install Chrome (Mac)
brew install chromium

# Or download manually
curl -L https://storage.googleapis.com/chrome-for-testing-public/131.0.6778.204/mac-x64/chrome-mac-x64.zip -o /tmp/chrome.zip
unzip /tmp/chrome.zip -d vendor/

# Set environment variable
export CUPRITE_BROWSER_PATH=/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome

# Test
bundle exec rails chrome:diagnose
```

## Chrome Version Updates

To update Chrome version in the future:

1. Check available versions: https://googlechromelabs.github.io/chrome-for-testing/
2. Update `CHROME_VERSION` in `bin/render-build.sh` (line 88)
3. Update `CHROME_VERSION` in `lib/tasks/chrome_diagnostics.rake` (line 237)
4. Test locally first
5. Deploy and verify

## Related Files

- `app/jobs/place_id_extraction_job.rb` - The job that uses Chrome
- `app/services/place_id_extraction/browser_path_resolver.rb` - Path resolution logic
- `app/controllers/business_manager/settings/integrations_controller.rb` - The UI
- `render.yaml` - Render configuration
- `bin/render-build.sh` - Build script

## Additional Resources

- Chrome for Testing: https://googlechromelabs.github.io/chrome-for-testing/
- Cuprite gem: https://github.com/rubycdp/cuprite
- Render deployment: https://render.com/docs
