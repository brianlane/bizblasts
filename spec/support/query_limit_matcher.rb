RSpec::Matchers.define :exceed_query_limit do |expected|
  supports_block_expectations

  match do |block|
    raise ArgumentError, 'exceed_query_limit only supports block expectations' unless block.respond_to?(:call)

    @actual = count_queries(&block)
    @actual > expected
  end

  failure_message do
    "expected query count to exceed #{expected}, but executed #{@actual}"
  end

  failure_message_when_negated do
    "expected query count not to exceed #{expected}, but executed #{@actual}"
  end

  description do
    "exceed query limit of #{expected}"
  end

  def count_queries
    query_count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      next if payload[:cached]
      next if payload[:name] == 'SCHEMA'

      query_count += 1
    end

    yield
    query_count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end

