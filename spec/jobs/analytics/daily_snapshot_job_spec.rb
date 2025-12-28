# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::DailySnapshotJob, type: :job do
  include ActiveJob::TestHelper

  let(:business) { create(:business) }
  let(:date) { Date.yesterday }

  describe '#perform' do
    context 'with analytics data' do
      before do
        # Create visitor sessions for yesterday
        create_list(:visitor_session, 3,
          business: business,
          session_start: date.beginning_of_day + 2.hours,
          page_view_count: 3
        )

        # Create some bounced sessions
        create(:visitor_session,
          business: business,
          session_start: date.beginning_of_day + 4.hours,
          page_view_count: 1,
          is_bounce: true
        )

        # Create converted session
        create(:visitor_session, :converted_booking,
          business: business,
          session_start: date.beginning_of_day + 6.hours
        )

        # Create page views
        business.visitor_sessions.each do |session|
          create_list(:page_view, 2,
            business: business,
            session_id: session.session_id,
            created_at: date.beginning_of_day + 3.hours
          )
        end
      end

      it 'creates a daily snapshot' do
        expect {
          described_class.perform_now(date)
        }.to change(AnalyticsSnapshot, :count).by(1)
      end

      it 'sets correct snapshot type and dates' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.snapshot_type).to eq('daily')
        expect(snapshot.period_start).to eq(date)
        expect(snapshot.period_end).to eq(date)
      end

      it 'calculates visitor metrics' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.total_sessions).to be > 0
        expect(snapshot.unique_visitors).to be > 0
      end

      it 'calculates bounce rate' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.bounce_rate).to be >= 0
        expect(snapshot.bounce_rate).to be <= 100
      end

      it 'calculates conversion metrics' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.total_conversions).to be >= 0
        expect(snapshot.conversion_rate).to be >= 0
      end

      it 'includes traffic source breakdown' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.traffic_sources).to be_a(Hash)
        expect(snapshot.traffic_sources.keys).to include('direct', 'organic', 'social', 'referral', 'paid')
      end

      it 'includes device breakdown' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.device_breakdown).to be_a(Hash)
      end

      it 'includes top pages' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.top_pages).to be_an(Array)
      end
    end

    context 'with no analytics data' do
      it 'creates a snapshot with zero values' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.total_sessions).to eq(0)
        expect(snapshot.total_page_views).to eq(0)
        expect(snapshot.bounce_rate).to eq(0.0)
      end
    end

    context 'when snapshot already exists' do
      before do
        create(:analytics_snapshot,
          business: business,
          snapshot_type: 'daily',
          period_start: date,
          period_end: date
        )
      end

      it 'does not create duplicate snapshot' do
        expect {
          described_class.perform_now(date)
        }.not_to change(AnalyticsSnapshot, :count)
      end
    end

    context 'with default date parameter' do
      it 'uses yesterday when no date provided' do
        expect {
          described_class.perform_now
        }.to change(AnalyticsSnapshot, :count).by(1)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.period_start).to eq(Date.yesterday)
      end
    end

    context 'with multiple businesses' do
      let(:other_business) { create(:business) }

      before do
        create(:visitor_session, business: business, session_start: date.beginning_of_day + 2.hours)
        create(:visitor_session, business: other_business, session_start: date.beginning_of_day + 2.hours)
      end

      it 'creates snapshots for all active businesses' do
        expect {
          described_class.perform_now(date)
        }.to change(AnalyticsSnapshot, :count).by(2)
      end
    end

    context 'when business processing fails' do
      let(:other_business) { create(:business) }

      before do
        create(:visitor_session, business: business, session_start: date.beginning_of_day + 2.hours)
        create(:visitor_session, business: other_business, session_start: date.beginning_of_day + 2.hours)

        # Make first business fail during metrics calculation
        allow_any_instance_of(described_class).to receive(:calculate_metrics).and_call_original
        allow_any_instance_of(described_class).to receive(:calculate_metrics)
          .with(business, date)
          .and_raise(StandardError.new('Test error'))
      end

      it 'logs error and continues with other businesses' do
        expect(Rails.logger).to receive(:error).at_least(:once)

        expect {
          described_class.perform_now(date)
        }.to change(AnalyticsSnapshot, :count).by(1)
      end
    end
  end

  describe 'booking metrics calculation' do
    context 'with bookings' do
      let!(:completed_booking) do
        service = create(:service, business: business, price: 100)
        create(:booking, :completed, business: business, service: service, created_at: date.beginning_of_day + 3.hours)
      end

      let!(:cancelled_booking) do
        service = create(:service, business: business, price: 50)
        create(:booking, :cancelled, business: business, service: service, created_at: date.beginning_of_day + 4.hours)
      end

      it 'calculates booking revenue correctly' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.booking_metrics['revenue']).to eq(100.0)
      end

      it 'calculates booking counts correctly' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.booking_metrics['total']).to eq(2)
        expect(snapshot.booking_metrics['completed']).to eq(1)
        expect(snapshot.booking_metrics['cancelled']).to eq(1)
      end

      it 'calculates average booking value correctly' do
        # Create another completed booking
        service = create(:service, business: business, price: 200)
        create(:booking, :completed, business: business, service: service, created_at: date.beginning_of_day + 5.hours)

        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.booking_metrics['avg_value']).to eq(150.0) # (100 + 200) / 2
      end
    end

    context 'without bookings' do
      it 'returns zero values' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        expect(snapshot.booking_metrics['total']).to eq(0)
        expect(snapshot.booking_metrics['revenue']).to eq(0.0)
        expect(snapshot.booking_metrics['avg_value']).to eq(0)
      end
    end
  end

  describe 'traffic sources calculation' do
    context 'with various traffic sources' do
      before do
        # Direct traffic (no referrer)
        create(:visitor_session, business: business, session_start: date.beginning_of_day + 1.hour,
               first_referrer_domain: nil)

        # Organic traffic
        create(:visitor_session, business: business, session_start: date.beginning_of_day + 2.hours,
               first_referrer_domain: 'google.com')

        # Social traffic
        create(:visitor_session, business: business, session_start: date.beginning_of_day + 3.hours,
               first_referrer_domain: 'facebook.com')

        # Paid traffic
        create(:visitor_session, business: business, session_start: date.beginning_of_day + 4.hours,
               utm_medium: 'cpc', first_referrer_domain: 'google.com')

        # Referral traffic
        create(:visitor_session, business: business, session_start: date.beginning_of_day + 5.hours,
               first_referrer_domain: 'example.com')
      end

      it 'calculates traffic source percentages' do
        described_class.perform_now(date)

        snapshot = AnalyticsSnapshot.last
        sources = snapshot.traffic_sources

        # Each source should be 20% (5 sessions total, 1 each)
        expect(sources['direct']).to eq(20.0)
        expect(sources['organic']).to eq(20.0)
        expect(sources['social']).to eq(20.0)
        expect(sources['paid']).to eq(20.0)
        expect(sources['referral']).to eq(20.0)
      end
    end
  end

  describe 'slow query monitoring' do
    it 'logs slow queries' do
      # Create a lot of data to potentially trigger slow query
      create_list(:visitor_session, 5,
        business: business,
        session_start: date.beginning_of_day + 2.hours
      )

      # The timed_query method will log if queries exceed threshold
      # This test just ensures the job completes without error
      expect {
        described_class.perform_now(date)
      }.not_to raise_error
    end
  end

  describe 'queue configuration' do
    it 'uses the analytics queue' do
      expect(described_class.new.queue_name).to eq('analytics')
    end
  end

  describe 'SLOW_QUERY_THRESHOLD constant' do
    it 'is set to 1 second' do
      expect(described_class::SLOW_QUERY_THRESHOLD).to eq(1.0)
    end
  end
end
