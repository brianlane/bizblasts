#!/usr/bin/env ruby

# Script to intelligently split tests for parallel execution with isolated databases
require 'find'
require 'fileutils'

class TestSplitter
  SPEC_CATEGORIES = {
    'models' => 'spec/models',
    'requests' => 'spec/requests', 
    'services' => 'spec/services',
    'integration' => 'spec/integration',
    'system' => 'spec/system',
    'controllers' => 'spec/controllers',
    'jobs' => 'spec/jobs',
    'mailers' => 'spec/mailers',
    'policies' => 'spec/policies',
    'features' => 'spec/features',
    'other' => ['spec/helpers', 'spec/lib', 'spec/views', 'spec/channels']
  }.freeze

  def initialize
    @base_db = 'bizblasts_test'
  end

  def find_tests_in_category(category)
    paths = SPEC_CATEGORIES[category]
    return [] unless paths

    tests = []
    paths = [paths] unless paths.is_a?(Array)
    
    paths.each do |path|
      next unless Dir.exist?(path)
      
      Find.find(path) do |file_path|
        if file_path.end_with?('_spec.rb')
          tests << file_path
        end
      end
    end
    
    tests.sort
  end

  def find_system_tests_split(group_num, total_groups = 3)
    tests = find_tests_in_category('system')
    return [] if tests.empty?

    # Same smart distribution as GitHub Actions
    tests_with_size = tests.map do |test|
      size = File.exist?(test) ? File.size(test) : 0
      [test, size]
    end
    
    # Sort by size descending
    tests_with_size.sort_by! { |_, size| -size }
    
    # Initialize groups
    groups = Array.new(total_groups) { { tests: [], total_size: 0 } }
    
    # Distribute using greedy algorithm
    tests_with_size.each do |test, size|
      smallest_group = groups.min_by { |group| group[:total_size] }
      smallest_group[:tests] << test
      smallest_group[:total_size] += size
    end
    
    return [] if group_num < 1 || group_num > total_groups
    groups[group_num - 1][:tests]
  end

  def database_name_for_category(category, group_num = nil)
    if category == 'system' && group_num
      "#{@base_db}_system_#{group_num}"
    else
      "#{@base_db}_#{category}"
    end
  end

  def map_category_to_test_env_number(category)
    # Map our categories to consistent TEST_ENV_NUMBER values
    # This ensures we use the same database names as database.yml expects
    category_map = {
      'models' => '1',
      'requests' => '2', 
      'services' => '3',
      'integration' => '4',
      'controllers' => '5',
      'jobs' => '6',
      'mailers' => '7',
      'policies' => '8',
      'features' => '9',
      'other' => '10',
      'system_1' => '11',
      'system_2' => '12',
      'system_3' => '13'
    }
    
    category_map[category] || '1'
  end

  def get_categories_with_tests
    categories = []
    
    SPEC_CATEGORIES.each do |category, _|
      if category == 'system'
        # Check if system tests exist and how many groups needed
        system_tests = find_tests_in_category('system')
        if system_tests.any?
          # Split system tests into 3 groups like GitHub Actions
          3.times do |i|
            group_tests = find_system_tests_split(i + 1, 3)
            categories << "system_#{i + 1}" if group_tests.any?
          end
        end
      else
        tests = find_tests_in_category(category)
        categories << category if tests.any?
      end
    end
    
    categories
  end

  def show_test_distribution
    puts "Test Distribution:"
    puts "=" * 50
    
    total_tests = 0
    
    SPEC_CATEGORIES.each do |category, _|
      if category == 'system'
        system_tests = find_tests_in_category('system')
        if system_tests.any?
          puts "\n#{category.upcase} (split into 3 groups):"
          3.times do |i|
            group_tests = find_system_tests_split(i + 1, 3)
            if group_tests.any?
              puts "  system_#{i + 1} (#{group_tests.length} tests) -> #{database_name_for_category('system', i + 1)}"
              total_tests += group_tests.length
            end
          end
        end
      else
        tests = find_tests_in_category(category)
        if tests.any?
          puts "#{category} (#{tests.length} tests) -> #{database_name_for_category(category)}"
          total_tests += tests.length
        end
      end
    end
    
    puts "\n" + "=" * 50
    puts "Total: #{total_tests} tests across isolated databases"
  end

  def get_tests_for_category(category)
    if category.start_with?('system_')
      group_num = category.split('_').last.to_i
      find_system_tests_split(group_num, 3)
    else
      find_tests_in_category(category)
    end
  end

  def run_category(category, processors: nil, coverage: false, fast: false)
    tests = get_tests_for_category(category)
    
    if tests.empty?
      puts "No tests found for category: #{category}"
      return true
    end

    # Get database info for this category
    actual_db_name = "bizblasts_test_#{category}"

    puts "Running #{category} tests (#{tests.length} tests) with database: #{actual_db_name}"
    
    # Ensure database exists before running tests
    unless database_exists?(actual_db_name)
      puts "Database #{actual_db_name} doesn't exist, setting it up..."
      unless setup_database(category)
        puts "Failed to setup database for #{category}"
        return false
      end
    end
    
    # Set up isolated environment using Rails database.yml configuration
    # Use a custom database name prefix for our split tests to avoid conflicts with parallel_rspec
    test_env_number = map_category_to_test_env_number(category)
    custom_db_name = "bizblasts_test_#{category}"
    
    env = {
      'RAILS_ENV' => 'test',
      'DATABASE_URL' => build_database_url(custom_db_name),
      'PARALLEL_TEST_FIRST_IS_1' => 'true',
      'DISABLE_DATABASE_ENVIRONMENT_CHECK' => '1'
    }

    # Performance optimizations
    if fast
      env.merge!({
        'SKIP_ASSET_COMPILATION' => 'true',
        'SKIP_DB_CLEAN' => 'true',
        'RAILS_DISABLE_ASSET_COMPILATION' => 'true',
        'NOCOV' => 'true'
      })
    end

    # Coverage settings
    if coverage
      env['COVERAGE'] = 'true'
    else
      env['NOCOV'] = 'true'
    end

    # Determine processors for this category
    actual_processors = processors || calculate_optimal_processors_for_category(category, tests.length)
    
    # Force single-threaded for problematic categories to avoid deadlocks
    if category == 'models' && actual_processors > 2
      puts "  Note: Reducing parallelism for models to avoid database conflicts"
      actual_processors = 2
    end
    
    if actual_processors > 1 && tests.length > 1
      env['PARALLEL_TEST_PROCESSORS'] = actual_processors.to_s
      cmd = ['bundle', 'exec', 'parallel_rspec'] + tests + ['-n', actual_processors.to_s]
      
      # Add fail-fast for parallel runs to stop on first failure
      cmd += ['--fail-fast'] unless fast
    else
      cmd = ['bundle', 'exec', 'rspec'] + tests + ['--format', 'progress']
    end

    puts "  Command: #{cmd.join(' ')}"
    puts "  Database: #{actual_db_name}"
    puts "  Processors: #{actual_processors}" if actual_processors > 1
    puts

    system(env, *cmd)
  end

  def calculate_optimal_processors_for_category(category, test_count)
    # Base processors on category and test count - be more conservative to avoid deadlocks
    base_processors = case category
    when /^system_/
      # System tests are slower and more prone to deadlocks, use fewer processors
      [test_count / 5, 1].max
    when 'integration', 'features'
      # Integration tests are medium speed and can have database conflicts
      [test_count / 4, 1].max
    when 'models', 'services'
      # Model tests can have foreign key issues with too much parallelism
      [test_count / 3, 2].max
    else
      # Other tests are usually safer for parallelism
      [test_count / 2, 2].max
    end

    # Cap based on system resources and be conservative
    max_processors = [get_system_max_processors / 2, 4].min
    [base_processors, max_processors].min
  end

  def get_system_max_processors
    if RUBY_PLATFORM.match?(/darwin/)
      `sysctl -n hw.physicalcpu`.to_i
    else
      `nproc`.to_i
    end
  end

  def setup_database(category)
    # Use our custom database naming to avoid conflicts with parallel_rspec
    db_name = "bizblasts_test_#{category}"

    puts "Setting up database: #{db_name}"

    # Use local database configuration
    username = ENV.fetch('DATABASE_USERNAME', 'brianlane')
    password = ENV.fetch('DATABASE_PASSWORD', '')
    host = ENV.fetch('DATABASE_HOST', 'localhost')
    port = ENV.fetch('DATABASE_PORT', '5432')

    # Build psql command with authentication - connect to template1
    psql_cmd = ['psql', '-h', host, '-p', port, '-d', 'template1']
    psql_cmd += ['-U', username] if username && !username.empty?
    
    # Set password if provided
    psql_env = {}
    psql_env['PGPASSWORD'] = password if password && !password.empty?

    # Drop and recreate database
    system(psql_env, *(psql_cmd + ['-c', "DROP DATABASE IF EXISTS #{db_name};"]))
    unless system(psql_env, *(psql_cmd + ['-c', "CREATE DATABASE #{db_name};"]))
      puts "Failed to create database: #{db_name}"
      return false
    end

    # Load schema using Rails with our custom database
    env = {
      'RAILS_ENV' => 'test',
      'DATABASE_URL' => build_database_url(db_name),
      'DISABLE_DATABASE_ENVIRONMENT_CHECK' => '1'
    }
    
    success = system(env, 'bundle', 'exec', 'rails', 'db:schema:load')
    
    unless success
      puts "Failed to setup database: #{db_name}"
      return false
    end

    puts "Database #{db_name} ready"
    true
  end

  def build_database_url(db_name)
    # Use local database configuration from database.yml defaults
    username = ENV.fetch('DATABASE_USERNAME', 'brianlane')
    password = ENV.fetch('DATABASE_PASSWORD', '')
    host = ENV.fetch('DATABASE_HOST', 'localhost')
    port = ENV.fetch('DATABASE_PORT', '5432')
    
    url = "postgresql://"
    url += "#{username}" if username && !username.empty?
    url += ":#{password}" if password && !password.empty?
    url += "@" if (username && !username.empty?) || (password && !password.empty?)
    url += "#{host}:#{port}/#{db_name}"
    url
  end

  def setup_all_databases(categories)
    puts "Setting up isolated databases for parallel testing..."
    puts

    failed_dbs = []
    
    categories.each do |category|
      unless setup_database(category)
        failed_dbs << category
      end
    end

    if failed_dbs.any?
      puts "Failed to setup databases for: #{failed_dbs.join(', ')}"
      return false
    end

    puts "All databases ready!"
    puts
    true
  end

  def cleanup_test_databases
    puts "Cleaning up test databases..."
    
    # Use local database configuration
    username = ENV.fetch('DATABASE_USERNAME', 'brianlane')
    password = ENV.fetch('DATABASE_PASSWORD', '')
    host = ENV.fetch('DATABASE_HOST', 'localhost')
    port = ENV.fetch('DATABASE_PORT', '5432')

    # Build psql command with authentication - connect to template1
    psql_cmd = ['psql', '-h', host, '-p', port, '-d', 'template1']
    psql_cmd += ['-U', username] if username && !username.empty?
    
    # Set password if provided
    psql_env = {}
    psql_env['PGPASSWORD'] = password if password && !password.empty?
    
    # Find all bizblasts_test_* databases (our custom split test databases)
    db_list_cmd = psql_cmd + ['-lqt']
    db_list = `#{psql_env.map{|k,v| "#{k}=#{v}"}.join(' ')} #{db_list_cmd.join(' ')} | cut -d \\| -f 1 | grep bizblasts_test_`.strip.split("\n")
    
    db_list.each do |db|
      db = db.strip
      next if db.empty?
      next if db == @base_db  # Keep the main test database
      
      puts "Dropping #{db}"
      system(psql_env, *(psql_cmd + ['-c', "DROP DATABASE IF EXISTS #{db};"]))
    end
    
    puts "Cleanup complete"
  end

  def database_exists?(db_name)    
    # Use local database configuration
    username = ENV.fetch('DATABASE_USERNAME', 'brianlane')
    password = ENV.fetch('DATABASE_PASSWORD', '')
    host = ENV.fetch('DATABASE_HOST', 'localhost')
    port = ENV.fetch('DATABASE_PORT', '5432')

    # Build psql command with authentication - connect to template1
    psql_cmd = ['psql', '-h', host, '-p', port, '-d', 'template1']
    psql_cmd += ['-U', username] if username && !username.empty?
    
    # Set password if provided
    psql_env = {}
    psql_env['PGPASSWORD'] = password if password && !password.empty?
    
    # Check if database exists
    result = `#{psql_env.map{|k,v| "#{k}=#{v}"}.join(' ')} #{psql_cmd.join(' ')} -lqt | cut -d \\| -f 1 | grep -w #{db_name}`
    !result.strip.empty?
  end
end

def show_help
  puts <<~HELP
    Usage: #{$0} [command] [options]
    
    Commands:
      list                    Show test distribution across categories
      run [category]          Run tests for specific category
      run-all                 Run all test categories in parallel
      setup [category]        Setup database for specific category
      setup-all              Setup all databases
      cleanup                 Remove all test databases except main
      
    Categories:
      models, requests, services, integration, controllers, jobs, mailers, policies, features, other
      system_1, system_2, system_3 (system tests split into 3 groups)
      
    Options:
      -p, --processors N      Number of parallel processes
      -c, --coverage          Enable code coverage
      -f, --fast              Fast mode (skip assets, coverage)
      -h, --help              Show this help
      
    Examples:
      #{$0} list                          # Show test distribution
      #{$0} run models                    # Run model tests
      #{$0} run system_1                  # Run system test group 1
      #{$0} run-all                       # Run all categories in parallel
      #{$0} run models -p 4 -c            # Run models with 4 processors and coverage
      #{$0} setup-all                     # Setup all isolated databases
      #{$0} cleanup                       # Clean up test databases
  HELP
end

# Main execution
if __FILE__ == $0
  splitter = TestSplitter.new
  
  command = ARGV[0]
  
  # Parse options
  processors = nil
  coverage = false
  fast = false
  
  i = 1
  while i < ARGV.length
    case ARGV[i]
    when '-p', '--processors'
      processors = ARGV[i + 1].to_i
      i += 2
    when '-c', '--coverage'
      coverage = true
      i += 1
    when '-f', '--fast'
      fast = true
      i += 1
    when '-h', '--help'
      show_help
      exit 0
    else
      i += 1
    end
  end
  
  case command
  when 'list'
    splitter.show_test_distribution
    
  when 'run'
    category = ARGV[1]
    unless category
      puts "Error: Must specify category to run"
      puts "Use: #{$0} list to see available categories"
      exit 1
    end
    
    # Parse options starting after the category argument
    i = 2
    while i < ARGV.length
      case ARGV[i]
      when '-p', '--processors'
        processors = ARGV[i + 1].to_i
        i += 2
      when '-c', '--coverage'
        coverage = true
        i += 1
      when '-f', '--fast'
        fast = true
        i += 1
      else
        i += 1
      end
    end
    
    success = splitter.run_category(category, processors: processors, coverage: coverage, fast: fast)
    exit(success ? 0 : 1)
    
  when 'run-all'
    categories = splitter.get_categories_with_tests
    
    if categories.empty?
      puts "No test categories found"
      exit 1
    end
    
    puts "Running all test categories in parallel..."
    puts "Categories: #{categories.join(', ')}"
    puts
    
    # Setup all databases first
    unless splitter.setup_all_databases(categories)
      exit 1
    end
    
    # Run all categories in parallel
    pids = []
    categories.each do |category|
      pid = fork do
        success = splitter.run_category(category, processors: processors, coverage: coverage, fast: fast)
        exit(success ? 0 : 1)
      end
      pids << pid
    end
    
    # Wait for all to complete
    results = pids.map { |pid| Process.wait2(pid) }
    failed = results.count { |_, status| !status.success? }
    
    if failed > 0
      puts "#{failed} test categories failed"
      exit 1
    else
      puts "All test categories passed!"
      exit 0
    end
    
  when 'setup'
    category = ARGV[1]
    unless category
      puts "Error: Must specify category to setup"
      exit 1
    end
    
    success = splitter.setup_database(category)
    exit(success ? 0 : 1)
    
  when 'setup-all'
    categories = splitter.get_categories_with_tests
    success = splitter.setup_all_databases(categories)
    exit(success ? 0 : 1)
    
  when 'cleanup'
    splitter.cleanup_test_databases
    
  when nil, '-h', '--help'
    show_help
    
  else
    puts "Unknown command: #{command}"
    puts "Use: #{$0} --help for usage information"
    exit 1
  end
end 