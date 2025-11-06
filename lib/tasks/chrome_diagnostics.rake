# frozen_string_literal: true

namespace :chrome do
  desc "Diagnose Chrome/Chromium installation for Cuprite"
  task diagnose: :environment do
    puts "=" * 80
    puts "Chrome/Chromium Installation Diagnostics"
    puts "=" * 80
    puts

    # 1. Check environment variables
    puts "1. Environment Variables:"
    puts "   CUPRITE_BROWSER_PATH: #{ENV['CUPRITE_BROWSER_PATH'] || '(not set)'}"
    puts "   BROWSER_PATH: #{ENV['BROWSER_PATH'] || '(not set)'}"
    puts "   CHROME_PATH: #{ENV['CHROME_PATH'] || '(not set)'}"
    puts

    # 2. Check what the resolver finds
    puts "2. BrowserPathResolver Result:"
    begin
      resolved_path = PlaceIdExtraction::BrowserPathResolver.resolve
      if resolved_path
        puts "   ✓ Resolved path: #{resolved_path}"

        # Check if file exists
        if File.exist?(resolved_path)
          puts "   ✓ File exists"

          # Check if executable
          if File.executable?(resolved_path)
            puts "   ✓ File is executable"
          else
            puts "   ✗ File is NOT executable"
            file_stat = File.stat(resolved_path)
            puts "     Permissions: #{file_stat.mode.to_s(8)}"
          end
        else
          puts "   ✗ File does NOT exist at resolved path"
        end
      else
        puts "   ✗ Could not resolve Chrome path"
      end
    rescue => e
      puts "   ✗ Error resolving path: #{e.message}"
    end
    puts

    # 3. Check project paths
    puts "3. Checking Project Paths:"
    project_paths = [
      Rails.root.join('vendor', 'chrome', 'chrome-linux64', 'chrome').to_s,
      Rails.root.join('vendor', 'chrome-linux64', 'chrome').to_s,
      Rails.root.join('vendor', 'chromium', 'chrome-linux64', 'chrome').to_s
    ]
    project_paths.each do |path|
      exists = File.exist?(path)
      executable = exists && File.executable?(path)
      status = if exists && executable
        "✓"
      elsif exists
        "✗ (not executable)"
      else
        "✗ (not found)"
      end
      puts "   #{status} #{path}"
    end
    puts

    # 4. Check system paths (Linux)
    puts "4. Checking System Paths (Linux):"
    system_paths = [
      '/opt/render/project/src/vendor/chrome/chrome-linux64/chrome',
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser'
    ]
    system_paths.each do |path|
      exists = File.exist?(path)
      executable = exists && File.executable?(path)
      status = if exists && executable
        "✓"
      elsif exists
        "✗ (not executable)"
      else
        "✗ (not found)"
      end
      puts "   #{status} #{path}"
    end
    puts

    # 5. Check vendor/chrome directory contents
    puts "5. Vendor Chrome Directory Contents:"
    vendor_chrome_dir = Rails.root.join('vendor', 'chrome')
    if Dir.exist?(vendor_chrome_dir)
      puts "   Directory exists: #{vendor_chrome_dir}"
      puts "   Contents:"
      Dir.glob("#{vendor_chrome_dir}/**/*").first(20).each do |path|
        type = File.directory?(path) ? "[DIR]" : "[FILE]"
        size = File.directory?(path) ? "" : " (#{File.size(path)} bytes)"
        executable = File.executable?(path) ? " [EXECUTABLE]" : ""
        relative_path = path.sub(vendor_chrome_dir.to_s, '')
        puts "     #{type} #{relative_path}#{size}#{executable}"
      end
    else
      puts "   ✗ Vendor chrome directory does not exist: #{vendor_chrome_dir}"
    end
    puts

    # 6. Check if we're on Render
    puts "6. Render Environment:"
    render_indicators = {
      'RENDER' => ENV['RENDER'],
      'RENDER_SERVICE_NAME' => ENV['RENDER_SERVICE_NAME'],
      'RENDER_INSTANCE_ID' => ENV['RENDER_INSTANCE_ID']
    }
    render_indicators.each do |key, value|
      puts "   #{key}: #{value || '(not set)'}"
    end
    puts

    # 7. Try to execute Chrome --version
    puts "7. Chrome Execution Test:"
    resolved_path = PlaceIdExtraction::BrowserPathResolver.resolve
    if resolved_path && File.exist?(resolved_path)
      begin
        require 'open3'
        version_output, status = Open3.capture2e(resolved_path, '--version')
        if status.success?
          puts "   ✓ Chrome executed successfully"
          puts "   Version: #{version_output.strip}"
        else
          puts "   ✗ Chrome failed to execute (exit code: #{status.exitstatus})"
          puts "   Output: #{version_output.lines.first(3).join}"

          # Try to diagnose missing libraries
          puts
          puts "   Diagnosing missing libraries:"
          ldd_output, ldd_status = Open3.capture2e('ldd', resolved_path)
          missing_libs = ldd_output.lines.select { |line| line.include?('not found') }
          if missing_libs.any?
            puts "   Missing libraries:"
            missing_libs.each { |lib| puts "     - #{lib.strip}" }
          else
            puts "   No missing libraries detected"
          end
        end
      rescue => e
        puts "   ✗ Error executing Chrome: #{e.message}"
      end
    else
      puts "   ✗ Cannot test - Chrome executable not found"
    end
    puts

    # 8. Check system dependencies
    puts "8. System Dependencies (Chrome requirements):"
    required_libs = %w[libnss3.so libgbm.so libgtk-3.so libglib-2.0.so libasound.so]
    begin
      ldconfig_output = `ldconfig -p 2>/dev/null`
      required_libs.each do |lib|
        found = ldconfig_output.include?(lib)
        puts "   #{found ? '✓' : '✗'} #{lib}"
      end
    rescue => e
      puts "   Unable to check system dependencies: #{e.message}"
    end
    puts

    # 9. Summary and recommendations
    puts "=" * 80
    puts "Summary and Recommendations:"
    puts "=" * 80

    if PlaceIdExtraction::BrowserPathResolver.resolve &&
       File.exist?(PlaceIdExtraction::BrowserPathResolver.resolve) &&
       File.executable?(PlaceIdExtraction::BrowserPathResolver.resolve)
      puts "✓ Chrome appears to be installed correctly"
      puts
      puts "If the job is still failing, try:"
      puts "  1. Check if Chrome can execute with dependencies: rake chrome:test_execute"
      puts "  2. Review recent deployment logs for Chrome download failures"
      puts "  3. Check Render logs during build time"
    else
      puts "✗ Chrome installation issue detected"
      puts
      puts "Recommendations:"
      puts "  1. Verify CUPRITE_BROWSER_PATH is set in Render dashboard"
      puts "  2. Redeploy to trigger Chrome download in render-build.sh"
      puts "  3. Check render-build.sh logs for Chrome download failures"
      puts "  4. Verify render.yaml has the correct packages list"
      puts "  5. Consider manually installing Chrome via Shell access"
    end
    puts "=" * 80
  end

  desc "Test Chrome execution with version check"
  task test_execute: :environment do
    resolved_path = PlaceIdExtraction::BrowserPathResolver.resolve

    if resolved_path.nil?
      puts "✗ Chrome path could not be resolved"
      exit 1
    end

    unless File.exist?(resolved_path)
      puts "✗ Chrome executable not found at: #{resolved_path}"
      exit 1
    end

    unless File.executable?(resolved_path)
      puts "✗ Chrome file is not executable at: #{resolved_path}"
      puts "File permissions: #{File.stat(resolved_path).mode.to_s(8)}"
      exit 1
    end

    puts "Testing Chrome execution..."
    require 'open3'
    version_output, status = Open3.capture2e(resolved_path, '--version')

    if status.success?
      puts "✓ Chrome executed successfully!"
      puts "Version: #{version_output.strip}"
      exit 0
    else
      puts "✗ Chrome failed to execute (exit code: #{status.exitstatus})"
      puts "Output:"
      puts version_output
      exit 1
    end
  end

  desc "Download and install Chrome (manual fallback)"
  task install: :environment do
    puts "Manually downloading and installing Chrome..."

    chrome_version = ENV['CHROME_VERSION'] || '131.0.6778.204'

    # SECURITY: Validate Chrome version format to prevent injection
    # Only allow numbers and dots (e.g., "131.0.6778.204")
    unless chrome_version.match?(/\A\d+\.\d+\.\d+\.\d+\z/)
      puts "ERROR: Invalid CHROME_VERSION format: #{chrome_version}"
      puts "Expected format: X.Y.Z.W (e.g., 131.0.6778.204)"
      puts "Using default version: 131.0.6778.204"
      chrome_version = '131.0.6778.204'
    end

    # Chrome for Testing publishes Linux builds as .zip files
    download_url = "https://storage.googleapis.com/chrome-for-testing-public/#{chrome_version}/linux64/chrome-linux64.zip"
    install_dir = Rails.root.join('vendor', 'chrome')

    puts "Chrome version: #{chrome_version}"
    puts "Download URL: #{download_url}"
    puts "Install directory: #{install_dir}"
    puts

    # Clean up old installation
    if Dir.exist?(install_dir)
      puts "Removing old Chrome installation..."
      FileUtils.rm_rf(install_dir)
    end

    FileUtils.mkdir_p(install_dir)

    # Download
    puts "Downloading Chrome..."
    download_path = '/tmp/chrome-linux64.zip'

    # Try to download with retries
    # SECURITY: Use array form of system() to prevent shell injection
    download_success = false
    3.times do |attempt|
      puts "Download attempt #{attempt + 1}/3..."
      if system('curl', '-fsSL', '--retry', '2', '--retry-delay', '5', '--connect-timeout', '30', '--max-time', '300', download_url, '-o', download_path)
        download_success = true
        break
      end
      puts "Download failed, retrying..." if attempt < 2
      sleep 5 if attempt < 2
    end

    abort("Failed to download Chrome after 3 attempts") unless download_success

    # Extract
    puts "Extracting Chrome..."
    temp_dir = '/tmp/chrome-download'
    FileUtils.mkdir_p(temp_dir)
    # SECURITY: Use array form of system() to prevent shell injection
    # Chrome for Testing publishes as .zip, so use unzip instead of tar
    system('unzip', '-q', download_path, '-d', temp_dir) || abort("Failed to extract Chrome (is unzip installed?)")

    # Move to vendor directory
    FileUtils.mv("#{temp_dir}/chrome-linux64", install_dir.to_s)

    # Set executable permissions
    chrome_binary = install_dir.join('chrome-linux64', 'chrome')
    FileUtils.chmod(0755, chrome_binary)

    # Cleanup
    FileUtils.rm_rf([temp_dir, download_path])

    puts "✓ Chrome installed successfully!"
    puts "Binary location: #{chrome_binary}"

    # Test execution
    puts
    puts "Testing Chrome execution..."
    require 'open3'
    version_output, status = Open3.capture2e(chrome_binary.to_s, '--version')

    if status.success?
      puts "✓ Chrome can execute successfully!"
      puts "Version: #{version_output.strip}"
    else
      puts "✗ Chrome installed but cannot execute"
      puts "Output: #{version_output}"
      puts
      puts "This usually means missing system dependencies."
      puts "Check render.yaml has all required packages."
    end
  end
end
