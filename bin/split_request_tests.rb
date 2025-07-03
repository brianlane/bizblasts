#!/usr/bin/env ruby

# Script to automatically split request specs into 2 balanced groups
require 'find'

def find_request_tests
  tests = []
  Find.find('spec/requests') do |path|
    tests << path if path.end_with?('_spec.rb')
  end
  tests.sort
end

def split_tests_evenly(tests, num_groups = 2)
  # Sort by file size (larger files likely have more/slower tests)
  tests_with_size = tests.map do |test|
    size = File.exist?(test) ? File.size(test) : 0
    [test, size]
  end

  # Sort by size descending to distribute larger tests first
  tests_with_size.sort_by! { |_, size| -size }

  # Initialize groups
  groups = Array.new(num_groups) { { tests: [], total_size: 0 } }

  # Distribute tests using a greedy algorithm (assign to smallest group)
  tests_with_size.each do |test, size|
    smallest_group = groups.min_by { |group| group[:total_size] }
    smallest_group[:tests] << test
    smallest_group[:total_size] += size
  end

  groups.map { |group| group[:tests] }
end

def main
  if ARGV[0] == '--help' || ARGV[0] == '-h'
    puts "Usage: #{$0} [group_number]"
    puts "  group_number: 1 or 2 (returns tests for that group)"
    puts "  no args: shows all groups"
    exit 0
  end

  tests = find_request_tests

  if tests.empty?
    puts "No request specs found"
    exit 0
  end

  groups = split_tests_evenly(tests, 2)

  if ARGV[0]
    group_num = ARGV[0].to_i
    if group_num >= 1 && group_num <= 2
      puts groups[group_num - 1].join(' ')
    else
      puts "Invalid group number. Use 1 or 2"
      exit 1
    end
  else
    groups.each_with_index do |group, index|
      puts "Group #{index + 1} (#{group.length} tests):"
      group.each { |test| puts "  #{test}" }
      puts
    end
  end
end

main if __FILE__ == $0 