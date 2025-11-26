#!/usr/bin/env ruby
# Performance profiling script for availability endpoint
# Usage: ruby script/performance_test.rb -u URL [-n REQUESTS] [-c CONCURRENCY] [-H HOST]

require 'optparse'
require 'net/http'
require 'uri'
require 'benchmark'

# Default options
options = {
  requests: 100,
  concurrency: 10,
  url: nil,
  host_header: nil
}

# Parse command-line arguments
OptionParser.new do |opts|
  opts.banner = "Usage: performance_test.rb [options]"

  opts.on('-u', '--url URL', 'Endpoint URL for availability check') do |v|
    options[:url] = v
  end

  opts.on('-n', '--requests N', Integer, 'Total number of requests (default: 100)') do |v|
    options[:requests] = v
  end

  opts.on('-c', '--concurrency C', Integer, 'Number of concurrent threads (default: 10)') do |v|
    options[:concurrency] = v
  end

  opts.on('-H', '--host HOST', 'Host header to send with requests (for subdomain testing)') do |v|
    options[:host_header] = v
  end

  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit
  end
end.parse!

# Validate required options
if options[:url].nil?
  warn 'Error: URL is required. Use -u or --url to specify the endpoint.'
  exit 1
end

uri = URI(options[:url])
total_requests = options[:requests]
concurrency = options[:concurrency]
host_header = options[:host_header]
requests_per_thread = (total_requests.to_f / concurrency).ceil

puts "Starting performance test..."
puts "Endpoint: #{uri}"
puts "Host header: #{host_header || '(none)'}"
puts "Total requests: #{total_requests}"
puts "Concurrency: #{concurrency}"
puts "Requests per thread: #{requests_per_thread}"
puts '-' * 50

# Helper to make request with optional Host header
def make_request(uri, host_header)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  http.open_timeout = 30
  http.read_timeout = 30
  
  request = Net::HTTP::Get.new(uri.request_uri)
  request['Host'] = host_header if host_header
  
  http.request(request)
end

# Array to collect response times
responses = []
mutex = Mutex.new

# Measure total time for all requests
total_time = Benchmark.realtime do
  threads = []

  concurrency.times do
    threads << Thread.new do
      requests_per_thread.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = make_request(uri, host_header)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        # Record elapsed time and output progress dot
        mutex.synchronize do
          responses << elapsed
          print '.' if responses.size % 10 == 0
        end

        # Log non-successful responses
        unless response.is_a?(Net::HTTPSuccess)
          mutex.synchronize { puts "\nNon-successful response: #{response.code} #{response.message}" }
        end
      end
    end
  end

  threads.each(&:join)
end

puts "\nCompleted #{responses.size} requests in #{total_time.round(2)} seconds."  
puts '-' * 50

# Calculate statistics
sorted = responses.sort
total = sorted.size
min = sorted.first
max = sorted.last
avg = sorted.sum / total
median = sorted[total / 2]
p90 = sorted[(total * 0.9).ceil - 1]
p95 = sorted[(total * 0.95).ceil - 1]

# Output results
puts "Min:    #{min.round(4)}s"
puts "Max:    #{max.round(4)}s"
puts "Average:#{avg.round(4)}s"
puts "Median: #{median.round(4)}s"
puts "90th percentile: #{p90.round(4)}s"
puts "95th percentile: #{p95.round(4)}s" 