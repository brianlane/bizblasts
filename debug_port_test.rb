#!/usr/bin/env ruby

require_relative 'spec/rails_helper'

puts "=== Debug Port Information ==="
puts "ENV['TEST_ENV_NUMBER']: #{ENV['TEST_ENV_NUMBER']}"
puts "Capybara.server_port: #{Capybara.server_port}"
puts "Capybara.app_host: #{Capybara.app_host}"

# Test business creation
business = FactoryBot.create(:business, host_type: 'subdomain')
puts "\nBusiness created:"
puts "  hostname: #{business.hostname}"
puts "  subdomain: #{business.subdomain}"
puts "  host_type: #{business.host_type}"

# Test the helper methods
include TenantHostHelpers

request = create_test_request
puts "\nTest request created:"
puts "  request.port: #{request.port}"
puts "  request.host: #{request.host}"
puts "  request.protocol: #{request.protocol}"

host = TenantHost.host_for(business, request)
puts "\nTenantHost.host_for result: #{host}"

url = TenantHost.url_for(business, request, '/tips/new')
puts "TenantHost.url_for result: #{url}"

puts "\n=== End Debug ==="