# frozen_string_literal: true

# Define tables to exclude and the order for truncation globally
EXCLUDED_TABLES = %w[spatial_ref_sys ar_internal_metadata schema_migrations].freeze
# Add tables with foreign keys pointing to others first
TRUNCATION_ORDER = %w[appointments users client_websites customers service_providers services companies service_templates].freeze

# Configure DatabaseCleaner to help with test isolation
RSpec.configure do |config|
  # Skip database cleaning entirely if SKIP_DB_CLEAN is set
  if ENV['SKIP_DB_CLEAN'] == 'true'
    puts "Database cleaning is DISABLED for faster performance (SKIP_DB_CLEAN=true)"
  else
    # Constants moved outside this block

    config.before(:suite) do
      # Allow cleaning of remote databases
      DatabaseCleaner.allow_remote_database_url = true

      # Use faster strategy with higher timeout for initial clean
      begin
        # Set a higher statement timeout for the deletion operation
        ActiveRecord::Base.connection.execute("SET statement_timeout = 60000") # 60 seconds
        DatabaseCleaner.clean_with(:deletion, except: EXCLUDED_TABLES)
      rescue => e
        puts "Warning: Failed to clean with deletion, falling back to truncation: #{e.message}"
        # Use truncation as a fallback, respecting order
        DatabaseCleaner.clean_with(:truncation, except: EXCLUDED_TABLES, pre_count: true, reset_ids: true)
      ensure
        # Reset the statement timeout
        ActiveRecord::Base.connection.execute("SET statement_timeout = 10000") # 10 seconds (increased default)
      end
    end

    # Default strategy is transaction which is fastest
    config.before(:each) do
      # Use transaction for most tests - fastest approach
      DatabaseCleaner.strategy = :transaction
    end

    # For system specs, use truncation respecting the order
    config.before(:each, type: :system) do
      # Truncate in specific order to avoid FK violations without superuser
      DatabaseCleaner.strategy = :truncation, {
        except: EXCLUDED_TABLES,
        # pre_count speeds up truncation when tables are already empty
        pre_count: true,
        # Reset auto-increment counters
        reset_ids: true
      }
    end

    # Seeds tests need special handling - faster deletion over truncation
    config.before(:each, type: :seed) do
      DatabaseCleaner.strategy = :deletion, { except: EXCLUDED_TABLES }
    end

    # Skip database cleaning for read-only tests to improve performance
    config.before(:each, readonly: true) do
      DatabaseCleaner.strategy = :null_strategy
    end

    config.before(:each) do
      # Start DatabaseCleaner unless skipped by metadata or strategy
      unless using_null_strategy? || metadata_for_example[:skip_db_cleaner_before]
        DatabaseCleaner.start
      end
    end

    config.after(:each) do
      # Clean with DatabaseCleaner unless skipped by metadata or strategy
      unless using_null_strategy? || metadata_for_example[:skip_db_cleaner_after]
        # Get the strategy object safely
        strategy = DatabaseCleaner.strategy rescue nil
        
        # Check if the strategy is truncation using its class name safely
        if strategy && strategy.class.name == 'DatabaseCleaner::ActiveRecord::Truncation'
          # We need to manually truncate in order if using truncation without superuser privileges
          # This is a workaround for the lack of referential integrity control.
          begin
            ActiveRecord::Base.connection.execute("SET statement_timeout = 60000") # 60 seconds for cleaning
            (TRUNCATION_ORDER - EXCLUDED_TABLES).each do |table|
              ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{ActiveRecord::Base.connection.quote_table_name(table)} RESTART IDENTITY CASCADE")
            end
          ensure
            ActiveRecord::Base.connection.execute("SET statement_timeout = 10000") # Reset timeout
          end
        elsif strategy
          # For other strategies (transaction, deletion), the regular clean works
          DatabaseCleaner.clean
        end
        # If strategy is nil or unrecognized, do nothing extra
      end
    end
  end
  
  # Helper method to access the metadata for the current example
  def metadata_for_example
    RSpec.current_example.metadata
  end
  
  # Helper method to check if using null strategy
  def using_null_strategy?
    # Safely check the strategy type - works with different DatabaseCleaner versions
    current_strategy = DatabaseCleaner.strategy rescue nil
    current_strategy.is_a?(DatabaseCleaner::NullStrategy) rescue false
  end
end 