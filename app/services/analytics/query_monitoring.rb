# frozen_string_literal: true

module Analytics
  # Shared module for monitoring and logging slow analytics queries
  # Include this module in analytics services to get consistent query timing and logging
  module QueryMonitoring
    extend ActiveSupport::Concern

    # Default threshold in seconds for logging slow queries
    SLOW_QUERY_THRESHOLD = 1.0

    included do
      class_attribute :query_threshold, default: SLOW_QUERY_THRESHOLD
    end

    # Execute a block and log if it exceeds the slow query threshold
    # @param name [String] Name of the query for logging
    # @param threshold [Float] Override threshold in seconds (optional)
    # @yield The block to execute and time
    # @return [Object] The result of the block
    def timed_query(name, threshold: nil, &block)
      threshold ||= self.class.query_threshold
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = block.call

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      log_query_timing(name, elapsed, threshold)
      track_query_metrics(name, elapsed) if respond_to?(:track_query_metrics, true)

      result
    end

    # Execute multiple queries in parallel and log timing
    # @param queries [Hash] Hash of query_name => proc
    # @return [Hash] Results keyed by query name
    def timed_parallel_queries(queries, threshold: nil)
      threshold ||= self.class.query_threshold
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Execute queries (could be parallelized in the future)
      results = {}
      queries.each do |name, query_proc|
        results[name] = timed_query(name, threshold: threshold, &query_proc)
      end

      total_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      if total_elapsed > threshold * queries.size
        Rails.logger.warn "[Analytics] Batch queries took #{total_elapsed.round(3)}s total"
      end

      results
    end

    private

    def log_query_timing(name, elapsed, threshold)
      service_name = self.class.name.demodulize

      if elapsed > threshold
        Rails.logger.warn "[#{service_name}] Slow query: #{name} took #{elapsed.round(3)}s (threshold: #{threshold}s)"
      elsif elapsed > threshold * 0.5 && Rails.env.development?
        # Log warning for queries approaching threshold in development
        Rails.logger.debug "[#{service_name}] Query approaching threshold: #{name} took #{elapsed.round(3)}s"
      end
    end

    # Override this method in including class to add custom metrics tracking
    # (e.g., StatsD, Prometheus, etc.)
    def track_query_metrics(name, elapsed)
      # No-op by default, override in including class for custom metrics
    end

    # Cache helper for expensive analytics calculations
    # @param key [String] Cache key
    # @param expires_in [ActiveSupport::Duration] Cache expiration
    # @yield The block to execute if cache miss
    # @return [Object] The cached or computed result
    def cached_analytics(key, expires_in: 1.hour, &block)
      full_key = "analytics:#{self.class.name.underscore}:#{key}"

      Rails.cache.fetch(full_key, expires_in: expires_in) do
        timed_query("cache_miss:#{key}", &block)
      end
    end

    # Batch cache fetch for multiple keys
    # @param keys [Array<String>] Cache keys
    # @param expires_in [ActiveSupport::Duration] Cache expiration
    # @yield [key] Block to compute value for cache miss
    # @return [Hash] Results keyed by original key
    def batch_cached_analytics(keys, expires_in: 1.hour)
      prefix = "analytics:#{self.class.name.underscore}:"
      full_keys = keys.map { |k| "#{prefix}#{k}" }

      # Fetch all existing cached values
      cached = Rails.cache.read_multi(*full_keys)

      # Compute missing values
      results = {}
      keys.each do |key|
        full_key = "#{prefix}#{key}"
        if cached.key?(full_key)
          results[key] = cached[full_key]
        else
          # Compute and cache the missing value
          value = yield(key)
          Rails.cache.write(full_key, value, expires_in: expires_in)
          results[key] = value
        end
      end

      results
    end
  end
end
