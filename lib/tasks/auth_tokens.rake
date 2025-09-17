# frozen_string_literal: true

namespace :auth_tokens do
  desc "Clean up expired auth tokens manually"
  task cleanup: :environment do
    puts "Starting manual auth token cleanup..."
    
    begin
      AuthTokenCleanupJob.cleanup_now!
      puts "✅ Auth token cleanup completed successfully"
    rescue => e
      puts "❌ Error during cleanup: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
      exit 1
    end
  end
  
  desc "Start the recurring auth token cleanup job"
  task start_cleanup: :environment do
    puts "Starting recurring auth token cleanup job..."
    
    begin
      AuthTokenCleanupJob.start_recurring_cleanup!
      puts "✅ Recurring cleanup job started"
    rescue => e
      puts "❌ Error starting cleanup job: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
      exit 1
    end
  end
  
  desc "Display auth token statistics"
  task stats: :environment do
    puts "Auth Token Statistics:"
    puts "=" * 40
    
    begin
      # Count total keys matching auth token pattern
      total_tokens = 0
      tokens_with_ttl = 0
      tokens_without_ttl = 0
      
      AuthToken.redis.scan_each(match: "#{AuthToken::REDIS_KEY_PREFIX}:*", count: 100) do |key|
        total_tokens += 1
        ttl = AuthToken.redis.ttl(key)
        
        if ttl > 0
          tokens_with_ttl += 1
        elsif ttl == -1
          tokens_without_ttl += 1
        end
        
        # Limit output for performance
        break if total_tokens >= 1000
      end
      
      puts "Total auth tokens: #{total_tokens}"
      puts "Tokens with TTL: #{tokens_with_ttl}"
      puts "Tokens without TTL (should be 0): #{tokens_without_ttl}"
      puts "Token TTL: #{AuthToken::TOKEN_TTL.inspect}"
      puts "Redis key prefix: #{AuthToken::REDIS_KEY_PREFIX}"
      
      if tokens_without_ttl > 0
        puts "\n⚠️  Warning: Found #{tokens_without_ttl} tokens without TTL!"
        puts "   Run 'rake auth_tokens:cleanup' to fix this."
      end
      
    rescue => e
      puts "❌ Error getting stats: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
      exit 1
    end
  end
  
  desc "Test auth token creation and cleanup"
  task test: :environment do
    puts "Testing auth token creation and cleanup..."
    
    begin
      # Create a test user if needed
      user = User.first || User.create!(
        email: 'test@example.com',
        first_name: 'Test',
        last_name: 'User',
        password: 'password123',
        role: :client
      )
      
      # Create test tokens
      puts "Creating test tokens..."
      tokens = []
      
      3.times do |i|
        token = AuthToken.create_for_user!(
          user,
          "https://example.com/test#{i}",
          '127.0.0.1',
          'Test Browser'
        )
        tokens << token
        puts "  Created token: #{token.token[0..8]}..."
      end
      
      puts "\nToken creation successful!"
      puts "Tokens created: #{tokens.length}"
      
      # Test cleanup
      puts "\nTesting cleanup..."
      cleanup_count = AuthToken.cleanup_expired!
      puts "Cleanup completed. Tokens cleaned: #{cleanup_count}"
      
      # Clean up test tokens
      puts "\nCleaning up test tokens..."
      tokens.each do |token|
        key = AuthToken.redis_key(token.token)
        AuthToken.redis.del(key)
      end
      
      puts "✅ Auth token test completed successfully"
      
    rescue => e
      puts "❌ Error during test: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
      exit 1
    end
  end
end