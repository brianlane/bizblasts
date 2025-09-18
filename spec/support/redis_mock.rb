# frozen_string_literal: true

require 'mock_redis'

# Configure MockRedis for test environment to avoid needing a real Redis server
RSpec.configure do |config|
  config.before(:each) do
    # Clear Redis data before each test to ensure clean state
    Redis.current.flushdb if Redis.current.respond_to?(:flushdb)
  end
end
