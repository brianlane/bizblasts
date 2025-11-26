#!/usr/bin/env ruby
# frozen_string_literal: true

# Duration-based test splitting for system specs
# System tests are browser-based and much slower (~12 seconds per test)
require 'find'

NUM_GROUPS = 5
SECONDS_PER_TEST = 12  # Browser tests are slow

def count_tests(file)
  content = File.read(file, encoding: 'UTF-8', invalid: :replace, undef: :replace)
  # System tests use both 'it' and 'scenario'
  content.scan(/^\s*(it|scenario)\s/).count
end

def find_system_tests
  tests = []
  Find.find('spec/system') do |path|
    if path.end_with?('_spec.rb')
      test_count = count_tests(path)
      estimated_duration = test_count * SECONDS_PER_TEST
      tests << { file: path, tests: test_count, duration: estimated_duration }
    end
  end
  tests
end

def split_tests_by_duration(tests, num_groups = NUM_GROUPS)
  # Sort by duration descending (largest first for better distribution)
  tests.sort_by! { |t| -t[:duration] }
  
  # Initialize groups with total duration tracking
  groups = Array.new(num_groups) { { files: [], total_duration: 0 } }
  
  # Greedy algorithm: assign each test file to the group with smallest total
  tests.each do |test|
    smallest_group = groups.min_by { |g| g[:total_duration] }
    smallest_group[:files] << test[:file]
    smallest_group[:total_duration] += test[:duration]
  end
  
  groups
end

def main
  if ARGV[0] == '--help' || ARGV[0] == '-h'
    puts "Usage: #{$0} [group_number]"
    puts "  group_number: 1-#{NUM_GROUPS} (returns tests for that group)"
    puts "  no args: shows all groups with estimated durations"
    exit 0
  end

  tests = find_system_tests
  
  if tests.empty?
    puts "No system tests found"
    exit 0
  end
  
  groups = split_tests_by_duration(tests, NUM_GROUPS)
  
  if ARGV[0]
    group_num = ARGV[0].to_i
    if group_num >= 1 && group_num <= NUM_GROUPS
      puts groups[group_num - 1][:files].join(' ')
    else
      puts "Invalid group number. Use 1-#{NUM_GROUPS}"
      exit 1
    end
  else
    total_tests = tests.sum { |t| t[:tests] }
    total_duration = tests.sum { |t| t[:duration] }
    puts "Total: #{tests.length} files, #{total_tests} tests, ~#{(total_duration / 60).round(1)}m estimated"
    puts
    groups.each_with_index do |group, index|
      file_count = group[:files].length
      test_count = 0
      group[:files].each { |f| test_count += count_tests(f) }
      puts "Group #{index + 1}: #{file_count} files, #{test_count} tests, ~#{(group[:total_duration] / 60).round(1)}m estimated"
      group[:files].each { |f| puts "  #{f}" }
      puts
    end
  end
end

main if __FILE__ == $0
