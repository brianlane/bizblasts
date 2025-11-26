#!/usr/bin/env ruby
# frozen_string_literal: true

# Duration-based test splitting for service/job/policy specs
# Estimates ~2.5 seconds per test based on CI profiling
require 'find'

NUM_GROUPS = 5
SECONDS_PER_TEST = 2.5

def count_tests(file)
  content = File.read(file, encoding: 'UTF-8', invalid: :replace, undef: :replace)
  content.scan(/^\s*it\s/).count
end

def find_service_tests
  tests = []
  
  %w[spec/services spec/jobs spec/policies].each do |dir|
    next unless Dir.exist?(dir)
    
    Find.find(dir) do |path|
      if path.end_with?('_spec.rb')
        test_count = count_tests(path)
        estimated_duration = test_count * SECONDS_PER_TEST
        tests << { file: path, tests: test_count, duration: estimated_duration }
      end
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

  tests = find_service_tests
  
  if tests.empty?
    puts "No service/job/policy specs found"
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
      puts "Group #{index + 1}: #{file_count} files, ~#{(group[:total_duration] / 60).round(1)}m estimated"
      group[:files].each { |f| puts "  #{f}" }
      puts
    end
  end
end

main if __FILE__ == $0
