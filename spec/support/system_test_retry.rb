# frozen_string_literal: true

# Retry mechanism for flaky system tests
module SystemTestRetry
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def it_with_retry(description, options = {}, &block)
      retries = options.delete(:retries) || 2
      
      it description, options do
        retry_count = 0
        begin
          instance_eval(&block)
        rescue => e
          retry_count += 1
          if retry_count <= retries && (
            e.message.include?('Ferrum::ProcessTimeoutError') ||
            e.message.include?('Capybara::ElementNotFound') ||
            e.message.include?('Net::ReadTimeout') ||
            e.message.include?('websocket url within')
          )
            puts "Test failed with: #{e.message}. Retrying (#{retry_count}/#{retries})..."
            sleep(retry_count) # Exponential backoff
            retry
          else
            raise e
          end
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include SystemTestRetry, type: :system
end 