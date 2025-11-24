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
      total_tokens = AuthToken.count
      valid_tokens = AuthToken.valid.count
      expired_tokens = AuthToken.expired.count
      used_tokens = AuthToken.where(used: true).count
      
      puts "Total auth tokens: #{total_tokens}"
      puts "Valid (unexpired, unused): #{valid_tokens}"
      puts "Expired: #{expired_tokens}"
      puts "Used: #{used_tokens}"
      puts "Token TTL: #{AuthToken::TOKEN_TTL.inspect}"
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
      
      # Clean up test tokens (DB-backed)
      puts "\nCleaning up test tokens..."
      tokens.each(&:destroy!)

      puts "✅ Auth token test completed successfully"
      
    rescue => e
      puts "❌ Error during test: #{e.message}"
      puts e.backtrace.join("\n") if ENV['VERBOSE']
      exit 1
    end
  end
end