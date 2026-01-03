# frozen_string_literal: true

module Analytics
  # Query budget enforcement to prevent runaway queries
  # Limits the number of records that can be loaded in analytics queries
  class QueryBudget
    class BudgetExceededError < StandardError; end

    def initialize
      @max_records = Rails.application.config.analytics.max_query_records
    end

    # Enforce query budget on an ActiveRecord relation
    # @param query [ActiveRecord::Relation] The query to check
    # @param description [String] Description of the query for error messages
    # @raise [BudgetExceededError] if query exceeds budget
    # @return [ActiveRecord::Relation] The original query if within budget
    def enforce!(query, description: 'Analytics query')
      # Use limit + 1 trick to detect if there are more records than the limit
      # This avoids counting the entire result set
      sample = query.limit(@max_records + 1).to_a

      if sample.size > @max_records
        Rails.logger.error "[QueryBudget] Budget exceeded for #{description}: >#{@max_records} records"

        # Alert to monitoring
        ActiveSupport::Notifications.instrument('analytics.query_budget_exceeded',
                                                query: description,
                                                max_records: @max_records)

        raise BudgetExceededError,
              "Query budget exceeded for #{description}: more than #{@max_records} records. " \
              "Please narrow your date range or add filters."
      end

      query
    end

    # Check if query is within budget without raising
    # @param query [ActiveRecord::Relation] The query to check
    # @return [Boolean] true if within budget
    def within_budget?(query)
      query.limit(@max_records + 1).count <= @max_records
    end

    # Get the maximum allowed records
    # @return [Integer] The maximum number of records
    def max_records
      @max_records
    end

    # Execute a query with automatic pagination if it exceeds budget
    # @param query [ActiveRecord::Relation] The query to execute
    # @param batch_size [Integer] Size of each batch (default: 1000)
    # @yield [Array] Yields each batch of records
    def paginate_if_needed(query, batch_size: 1000)
      return enum_for(:paginate_if_needed, query, batch_size: batch_size) unless block_given?

      # Check if we need to paginate
      if within_budget?(query)
        yield query.to_a
      else
        # Paginate in batches
        offset = 0
        loop do
          batch = query.limit(batch_size).offset(offset).to_a
          break if batch.empty?

          yield batch

          offset += batch_size

          # Safety check to prevent infinite loops
          if offset > @max_records
            Rails.logger.warn "[QueryBudget] Pagination stopped at max_records limit"
            break
          end
        end
      end
    end
  end
end
