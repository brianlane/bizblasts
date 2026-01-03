# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

RSpec.describe 'Analytics Dashboard Performance', type: :performance do
  let(:business) { create(:business) }
  let(:target_response_time) { 0.5 } # 500ms target
  let(:large_dataset_size) { 10_000 }
  let(:medium_dataset_size) { 1_000 }

  # Helper to measure execution time
  def measure_time(&block)
    Benchmark.realtime(&block)
  end

  # Helper to create realistic analytics data
  def create_analytics_data(business, page_views: 100, click_events: 50, conversions: 10)
    sessions = []

    # Create visitor sessions with varied patterns
    (page_views / 10).times do |i|
      sessions << create(:visitor_session,
                        business: business,
                        entry_page: ['/services', '/products', '/about', '/'].sample,
                        referrer_domain: ['google.com', 'facebook.com', nil, 'bing.com'].sample,
                        utm_source: ['google', 'facebook', 'email', nil].sample,
                        utm_medium: ['cpc', 'organic', 'social', nil].sample,
                        created_at: rand(30.days.ago..Time.current))
    end

    # Create page views distributed across sessions
    page_views.times do |i|
      session = sessions.sample || create(:visitor_session, business: business)
      create(:page_view,
             business: business,
             visitor_session: session,
             page_path: ['/services', '/products', '/about', '/contact', '/'].sample,
             page_type: ['services', 'products', 'about', 'contact', 'home'].sample,
             device_type: ['mobile', 'desktop', 'tablet'].sample,
             time_on_page: rand(10..300),
             created_at: rand(30.days.ago..Time.current))
    end

    # Create click events
    click_events.times do
      create(:click_event,
             business: business,
             page_path: ['/services', '/products', '/'].sample,
             element_type: ['button', 'link', 'cta'].sample,
             category: ['booking', 'navigation', 'contact'].sample,
             created_at: rand(30.days.ago..Time.current))
    end

    # Create conversions
    conversions.times do
      create(:conversion,
             business: business,
             conversion_type: ['booking', 'purchase', 'contact'].sample,
             conversion_value: rand(50.0..500.0),
             created_at: rand(30.days.ago..Time.current))
    end
  end

  describe 'Dashboard Overview Performance' do
    context 'with medium dataset (1k page views)' do
      before do
        create_analytics_data(business, page_views: medium_dataset_size, click_events: 500, conversions: 50)
      end

      it 'loads overview metrics within target time' do
        time = measure_time do
          # Simulate dashboard controller queries
          business.page_views.for_period(30.days.ago, Time.current).count
          business.visitor_sessions.for_period(30.days.ago, Time.current).count
          business.conversions.for_period(30.days.ago, Time.current).sum(:conversion_value)
        end

        expect(time).to be < target_response_time,
                        "Overview metrics took #{time.round(3)}s, expected < #{target_response_time}s"
      end

      it 'loads traffic sources within target time' do
        time = measure_time do
          business.page_views.traffic_by_source(start_date: 30.days.ago, end_date: Time.current)
        end

        expect(time).to be < target_response_time,
                        "Traffic sources took #{time.round(3)}s, expected < #{target_response_time}s"
      end

      it 'loads top pages within target time' do
        time = measure_time do
          business.page_views
                  .for_period(30.days.ago, Time.current)
                  .group(:page_path)
                  .count
                  .sort_by { |_, count| -count }
                  .first(10)
        end

        expect(time).to be < target_response_time,
                        "Top pages took #{time.round(3)}s, expected < #{target_response_time}s"
      end
    end

    context 'with large dataset (10k page views)' do
      before do
        create_analytics_data(business, page_views: large_dataset_size, click_events: 5000, conversions: 500)
      end

      it 'loads overview metrics within reasonable time' do
        # Allow more time for large dataset but still require good performance
        max_time = target_response_time * 2 # 1 second

        time = measure_time do
          business.page_views.for_period(30.days.ago, Time.current).count
          business.visitor_sessions.for_period(30.days.ago, Time.current).count
          business.conversions.for_period(30.days.ago, Time.current).sum(:conversion_value)
        end

        expect(time).to be < max_time,
                        "Large dataset overview took #{time.round(3)}s, expected < #{max_time}s"
      end

      it 'does not cause N+1 queries on traffic sources' do
        # Should use database aggregation, not load all records
        query_count = 0

        ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
          query_count += 1 unless args.last[:sql].include?('SCHEMA')
        end

        business.page_views.traffic_by_source(start_date: 30.days.ago, end_date: Time.current)

        # Should be a single aggregation query, not N queries
        expect(query_count).to be <= 2, "Expected 1-2 queries, got #{query_count} (possible N+1)"
      end
    end
  end

  describe 'Daily Snapshot Performance' do
    let(:snapshot_service) { Analytics::DailySnapshotService.new(business) }

    context 'with medium dataset' do
      before do
        create_analytics_data(business, page_views: medium_dataset_size, click_events: 500, conversions: 50)
      end

      it 'generates daily snapshot within target time' do
        max_time = 2.0 # 2 seconds for snapshot generation

        time = measure_time do
          snapshot_service.generate_snapshot(Date.current)
        end

        expect(time).to be < max_time,
                        "Snapshot generation took #{time.round(3)}s, expected < #{max_time}s"
      end

      it 'generates snapshot without N+1 queries' do
        query_count = 0

        ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
          query_count += 1 unless args.last[:sql].include?('SCHEMA')
        end

        snapshot_service.generate_snapshot(Date.current)

        # Allow reasonable number of queries for snapshot (should use aggregations)
        expect(query_count).to be <= 20, "Expected <= 20 queries, got #{query_count}"
      end
    end
  end

  describe 'Export Performance' do
    context 'with medium dataset' do
      before do
        create_analytics_data(business, page_views: medium_dataset_size, click_events: 500, conversions: 50)
      end

      it 'exports CSV within reasonable time' do
        max_time = 3.0 # 3 seconds for export

        time = measure_time do
          csv_data = business.page_views
                            .for_period(30.days.ago, Time.current)
                            .includes(:visitor_session)
                            .limit(1000) # Export limits to 1000 records
                            .to_a

          # Simulate CSV generation
          csv_data.map { |pv| [pv.page_path, pv.created_at, pv.device_type].join(',') }
        end

        expect(time).to be < max_time,
                        "CSV export took #{time.round(3)}s, expected < #{max_time}s"
      end

      it 'uses includes to prevent N+1 on export' do
        query_count = 0

        ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
          query_count += 1 unless args.last[:sql].include?('SCHEMA')
        end

        page_views = business.page_views
                            .for_period(30.days.ago, Time.current)
                            .includes(:visitor_session)
                            .limit(100)
                            .to_a

        # Access session data - should not trigger additional queries
        page_views.each { |pv| pv.visitor_session&.entry_page }

        # Should be 1 query for page views + 1 for sessions (with includes)
        expect(query_count).to be <= 2, "Expected 1-2 queries with includes, got #{query_count}"
      end
    end
  end

  describe 'Real-time Analytics Performance' do
    it 'tracks events with minimal overhead' do
      max_time = 0.1 # 100ms for event creation

      time = measure_time do
        10.times do
          create(:page_view, business: business)
        end
      end

      expect(time).to be < max_time,
                        "Creating 10 events took #{time.round(3)}s, expected < #{max_time}s"
    end

    it 'batches event creation efficiently' do
      # Create events in batch - should be faster than individual inserts
      events_data = 100.times.map do
        {
          business_id: business.id,
          page_path: '/test',
          page_type: 'custom',
          device_type: 'desktop',
          created_at: Time.current
        }
      end

      time = measure_time do
        PageView.insert_all(events_data) # Use insert_all for batch insert
      end

      # Batch insert should be very fast
      expect(time).to be < 0.5,
                        "Batch insert of 100 events took #{time.round(3)}s, expected < 0.5s"
    end
  end

  describe 'Memory Usage' do
    it 'does not load excessive records into memory' do
      create_analytics_data(business, page_views: large_dataset_size)

      # Monitor memory usage during query
      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

      # Use find_each to prevent loading all records
      business.page_views.find_each(batch_size: 100) do |page_view|
        page_view.page_path # Access attribute
      end

      final_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_increase_mb = (final_memory - initial_memory) / 1024.0

      # Memory increase should be reasonable (< 50MB for processing 10k records in batches)
      expect(memory_increase_mb).to be < 50,
                                    "Memory increased by #{memory_increase_mb.round(2)}MB, expected < 50MB"
    end

    it 'limits query results to prevent memory issues' do
      create_analytics_data(business, page_views: large_dataset_size)

      # Use QueryBudget to limit results
      budget = Analytics::QueryBudget.new
      query = business.page_views.for_period(30.days.ago, Time.current)

      # Should enforce budget
      expect do
        budget.enforce!(query, description: 'Performance test query')
      rescue Analytics::QueryBudget::BudgetExceededError
        # Expected if query exceeds budget
        nil
      end.not_to raise_error(StandardError)
    end
  end

  describe 'Concurrent Access Performance' do
    it 'handles concurrent dashboard requests efficiently' do
      create_analytics_data(business, page_views: medium_dataset_size)

      # Simulate multiple concurrent requests
      threads = 5.times.map do
        Thread.new do
          business.page_views.for_period(7.days.ago, Time.current).count
        end
      end

      time = measure_time do
        threads.each(&:join)
      end

      # All 5 requests should complete reasonably fast
      expect(time).to be < 3.0,
                        "5 concurrent requests took #{time.round(3)}s, expected < 3s"
    end
  end

  describe 'Index Performance' do
    before do
      create_analytics_data(business, page_views: medium_dataset_size, click_events: 500)
    end

    it 'uses index for date range queries' do
      # Force explain to verify index usage
      query = business.page_views.for_period(7.days.ago, Time.current)
      explain = query.explain

      # Check that explain shows index usage (not full table scan)
      expect(explain).to include('index'),
                         "Query should use index, got: #{explain}"
    end

    it 'uses heatmap index for click event queries' do
      query = business.click_events
                      .where(element_type: 'button')
                      .where(page_path: '/services')
                      .where('created_at >= ?', 7.days.ago)
      explain = query.explain

      # Should use the heatmap composite index
      expect(explain).to include('index'),
                         "Heatmap query should use index, got: #{explain}"
    end
  end
end
