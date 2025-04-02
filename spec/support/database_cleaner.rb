# frozen_string_literal: true

# Configure DatabaseCleaner to help with test isolation
RSpec.configure do |config|
  # Clean database between tests with truncation strategy for system tests
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  # Default strategy is transaction which is fastest
  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  # For system and request specs, use truncation
  config.before(:each, type: :system) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each, type: :request) do
    DatabaseCleaner.strategy = :truncation
  end

  # Seeds tests need special handling - truncation over transaction
  config.before(:each, type: :seed) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner.start unless metadata_for_example.has_key?(:no_db_clean)
  end

  config.after(:each) do
    DatabaseCleaner.clean unless metadata_for_example.has_key?(:no_db_clean)
  end
  
  # Helper method to access the metadata for the current example
  def metadata_for_example
    RSpec.current_example.metadata
  end
end 