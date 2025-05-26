# frozen_string_literal: true

namespace :tailwind do
  desc "Build Tailwind CSS without database dependencies"
  task :build_standalone do
    puts "Building Tailwind CSS in standalone mode..."
    
    # Set environment variables to skip database operations
    ENV['RAILS_DISABLE_ASSET_COMPILATION'] = 'true'
    ENV['SKIP_SOLID_QUEUE_SETUP'] = 'true'
    ENV['DISABLE_DATABASE_ENVIRONMENT_CHECK'] = '1'
    
    # Create output directory
    output_dir = Rails.root.join('app', 'assets', 'builds')
    FileUtils.mkdir_p(output_dir)
    
    input_file = Rails.root.join('app', 'assets', 'tailwind', 'application.css')
    output_file = output_dir.join('tailwind.css')
    
    unless File.exist?(input_file)
      puts "Error: Tailwind input file not found at #{input_file}"
      exit 1
    end
    
    # Try different approaches to build Tailwind
    success = false
    
    # Approach 1: Use tailwindcss-rails gem's built-in command
    begin
      require 'tailwindcss-rails'
      puts "Using tailwindcss-rails gem..."
      
      # Get the tailwindcss executable path from the gem
      tailwindcss_path = Tailwindcss::Commands.executable
      
      cmd = [
        tailwindcss_path,
        '-i', input_file.to_s,
        '-o', output_file.to_s,
        '--config', Rails.root.join('tailwind.config.js').to_s,
        '--minify'
      ]
      
      puts "Running: #{cmd.join(' ')}"
      system(*cmd, exception: true)
      success = true
      puts "✓ Tailwind CSS built successfully using tailwindcss-rails"
      
    rescue => e
      puts "Failed to use tailwindcss-rails: #{e.message}"
    end
    
    # Approach 2: Try system tailwindcss if available
    unless success
      begin
        puts "Trying system tailwindcss command..."
        cmd = [
          'tailwindcss',
          '-i', input_file.to_s,
          '-o', output_file.to_s,
          '--config', Rails.root.join('tailwind.config.js').to_s,
          '--minify'
        ]
        
        puts "Running: #{cmd.join(' ')}"
        system(*cmd, exception: true)
        success = true
        puts "✓ Tailwind CSS built successfully using system tailwindcss"
        
      rescue => e
        puts "Failed to use system tailwindcss: #{e.message}"
      end
    end
    
    # Approach 3: Fallback to copying the input file (basic CSS)
    unless success
      puts "Falling back to copying input file..."
      FileUtils.cp(input_file, output_file)
      puts "⚠ Copied raw Tailwind input file as fallback"
      success = true
    end
    
    if success && File.exist?(output_file)
      file_size = File.size(output_file)
      puts "✓ Tailwind CSS build completed: #{output_file} (#{file_size} bytes)"
    else
      puts "✗ Failed to build Tailwind CSS"
      exit 1
    end
  end
end 