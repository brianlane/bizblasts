#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify Tailwind CSS can be built without database access
puts "Testing Tailwind CSS build without database..."

# Set environment variables to simulate CI environment
ENV['RAILS_DISABLE_ASSET_COMPILATION'] = 'true'
ENV['SKIP_SOLID_QUEUE_SETUP'] = 'true'
ENV['DISABLE_DATABASE_ENVIRONMENT_CHECK'] = '1'
ENV['RAILS_ENV'] = 'test'

# Remove any existing build files
build_dir = File.join(__dir__, '..', 'app', 'assets', 'builds')
tailwind_file = File.join(build_dir, 'tailwind.css')

if File.exist?(tailwind_file)
  puts "Removing existing Tailwind build file..."
  File.delete(tailwind_file)
end

# Test 1: Try the standalone build script
puts "\n=== Test 1: Standalone build script ==="
system("#{File.join(__dir__, '..', 'bin', 'build-tailwind-standalone.sh')}")

if File.exist?(tailwind_file)
  puts "✓ Standalone build script succeeded"
  file_size = File.size(tailwind_file)
  puts "  Generated file: #{tailwind_file} (#{file_size} bytes)"
else
  puts "✗ Standalone build script failed"
end

# Clean up for next test
File.delete(tailwind_file) if File.exist?(tailwind_file)

# Test 2: Try the custom Rake task
puts "\n=== Test 2: Custom Rake task ==="
system("bundle exec rake tailwind:build_standalone")

if File.exist?(tailwind_file)
  puts "✓ Custom Rake task succeeded"
  file_size = File.size(tailwind_file)
  puts "  Generated file: #{tailwind_file} (#{file_size} bytes)"
else
  puts "✗ Custom Rake task failed"
end

# Test 3: Verify SolidQueue initializer doesn't break
puts "\n=== Test 3: SolidQueue initializer safety ==="
begin
  # Try to load the initializer without database
  load File.join(__dir__, '..', 'config', 'initializers', 'solid_queue.rb')
  puts "✓ SolidQueue initializer loaded safely without database"
rescue => e
  puts "✗ SolidQueue initializer failed: #{e.message}"
end

puts "\n=== Test Summary ==="
if File.exist?(tailwind_file)
  puts "✓ Tailwind CSS build is working!"
  puts "  Final file: #{tailwind_file}"
  puts "  Size: #{File.size(tailwind_file)} bytes"
  
  # Show first few lines of the generated CSS
  puts "\n  First few lines of generated CSS:"
  File.open(tailwind_file, 'r') do |f|
    3.times do
      line = f.gets
      break unless line
      puts "    #{line.chomp}"
    end
  end
else
  puts "✗ Tailwind CSS build is not working"
  exit 1
end 