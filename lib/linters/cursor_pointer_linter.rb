#!/usr/bin/env ruby
# frozen_string_literal: true

# Cursor Pointer Linter
# Checks ERB templates for interactive elements missing cursor-pointer class
#
# Usage:
#   ruby lib/linters/cursor_pointer_linter.rb
#   ruby lib/linters/cursor_pointer_linter.rb --fix
#   ruby lib/linters/cursor_pointer_linter.rb app/views/specific_file.html.erb

require 'optparse'
require 'pathname'

class CursorPointerLinter
  # Interactive elements that should have cursor-pointer
  BUTTON_PATTERNS = [
    # button_to helper
    /button_to\s+["'][^"']*["'][^>]*class:\s*["']([^"']*)["']/,
    # link_to with button-like classes
    /link_to\s+["'][^"']*["'][^>]*class:\s*["']([^"']*(?:btn|button)[^"']*)["']/,
    # HTML button elements
    /<button[^>]*class=["']([^"']*)["']/,
    # Form submit buttons
    /form\.submit[^>]*class:\s*["']([^"']*)["']/,
    # Input submit buttons
    /<input[^>]*type=["'](?:submit|button)["'][^>]*class=["']([^"']*)["']/
  ].freeze

  # Elements that should be excluded from checking
  EXCLUDE_PATTERNS = [
    /disabled.*cursor-not-allowed/,
    /cursor-default/,
    /cursor-wait/,
    /cursor-help/
  ].freeze

  def initialize(options = {})
    @fix_mode = options[:fix]
    @verbose = options[:verbose]
    @files = options[:files] || default_view_files
    @errors = []
  end

  def run
    puts "🔍 Checking #{@files.length} files for missing cursor-pointer..." if @verbose

    @files.each do |file|
      check_file(file)
    end

    print_results
    @errors.empty? ? 0 : 1
  end

  private

  def default_view_files
    Dir.glob('app/views/**/*.html.erb') + Dir.glob('app/views/**/*.html.haml')
  end

  def check_file(file_path)
    return unless File.exist?(file_path)

    content = File.read(file_path)
    lines = content.lines
    
    lines.each_with_index do |line, index|
      line_number = index + 1
      check_line(file_path, line, line_number, content)
    end
  end

  def check_line(file_path, line, line_number, full_content)
    BUTTON_PATTERNS.each do |pattern|
      next unless line.match?(pattern)
      
      match = line.match(pattern)
      next unless match

      css_classes = match[1] || ''
      
      # Skip if already has cursor class or is excluded
      next if has_cursor_class?(css_classes)
      next if excluded_element?(line)
      
      # Extract the full element for context
      element_context = extract_element_context(full_content, line_number)
      
      error = {
        file: file_path,
        line: line_number,
        content: line.strip,
        element: element_context,
        css_classes: css_classes,
        pattern: pattern.source
      }

      if @fix_mode
        fix_line(file_path, full_content, line_number, css_classes)
      else
        @errors << error
      end
    end
  end

  def has_cursor_class?(css_classes)
    css_classes.include?('cursor-pointer') || 
    css_classes.include?('cursor-not-allowed') ||
    css_classes.include?('cursor-default') ||
    css_classes.include?('cursor-wait')
  end

  def excluded_element?(line)
    EXCLUDE_PATTERNS.any? { |pattern| line.match?(pattern) }
  end

  def extract_element_context(content, line_number)
    lines = content.lines
    start_line = [line_number - 2, 0].max
    end_line = [line_number + 1, lines.length - 1].min
    
    lines[start_line..end_line].map.with_index(start_line + 1) do |line, idx|
      marker = idx == line_number ? '>' : ' '
      "#{marker} #{idx.to_s.rjust(3)}: #{line}"
    end.join
  end

  def fix_line(file_path, content, line_number, css_classes)
    lines = content.lines
    line = lines[line_number - 1]
    
    # Add cursor-pointer to the class list
    new_classes = css_classes.empty? ? 'cursor-pointer' : "cursor-pointer #{css_classes}"
    
    # Replace the class attribute
    BUTTON_PATTERNS.each do |pattern|
      if line.match?(pattern)
        new_line = line.gsub(pattern) do |match|
          match.gsub(/class:\s*["']([^"']*)["']/, "class: \"#{new_classes}\"")
                .gsub(/class=["']([^"']*)["']/, "class=\"#{new_classes}\"")
        end
        
        lines[line_number - 1] = new_line
        File.write(file_path, lines.join)
        
        puts "✅ Fixed: #{file_path}:#{line_number}" if @verbose
        return
      end
    end
  end

  def print_results
    if @errors.empty?
      puts "✅ All interactive elements have cursor-pointer class!"
      return
    end

    puts "\n❌ Found #{@errors.length} interactive elements missing cursor-pointer:\n"
    
    @errors.group_by { |e| e[:file] }.each do |file, file_errors|
      puts "\n📄 #{file}:"
      
      file_errors.each do |error|
        puts "  Line #{error[:line]}:"
        puts "    Current: #{error[:content]}"
        puts "    Classes: '#{error[:css_classes]}'"
        puts "    Context:"
        puts error[:element].gsub(/^/, '      ')
        puts
      end
    end

    puts "\n💡 To automatically fix these issues, run:"
    puts "    ruby lib/linters/cursor_pointer_linter.rb --fix"
    puts "\n📋 Or add cursor-pointer manually to the class attributes above."
  end
end

# CLI Interface
if __FILE__ == $0
  options = {
    fix: false,
    verbose: false,
    files: nil
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options] [files...]"
    
    opts.on('--fix', 'Automatically fix missing cursor-pointer classes') do
      options[:fix] = true
    end
    
    opts.on('-v', '--verbose', 'Show detailed output') do
      options[:verbose] = true
    end
    
    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end.parse!

  # Use provided files or default to all view files
  options[:files] = ARGV.empty? ? nil : ARGV

  linter = CursorPointerLinter.new(options)
  exit_code = linter.run
  exit(exit_code)
end