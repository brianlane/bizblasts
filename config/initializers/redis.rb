# frozen_string_literal: true

require 'redis'

if Rails.env.test?
  # In test environment, use MockRedis for consistency
  require 'mock_redis'
  
  # Define Redis.current method for test environment
  Redis.define_singleton_method(:current) do
    @current ||= MockRedis.new
  end
else
  # Production/Development: use real Redis
  redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
  
  # Define Redis.current method for production/development environment
  Redis.define_singleton_method(:current) do
    @current ||= Redis.new(url: redis_url)
  end
end
