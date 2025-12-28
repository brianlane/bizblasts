# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::DashboardService, type: :service do
  let(:business) { create(:business) }
  let(:service) { described_class.new(business) }

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe '#quick_stats' do
    context 'with no data' do
      it 'returns zero values' do
        stats = service.quick_stats
        
        expect(stats[:unique_visitors]).to eq(0)
        expect(stats[:page_views]).to eq(0)
        expect(stats[:bounce_rate]).to eq(0)
        expect(stats[:conversions]).to eq(0)
      end
    end

    context 'with visitor data' do
      before do
        # Create visitor sessions with valid hex fingerprints
        create(:visitor_session, business: business, visitor_fingerprint: 'a1b2c3d4e5f60001')
        create(:visitor_session, business: business, visitor_fingerprint: 'a1b2c3d4e5f60002')
        create(:visitor_session, :bounce, business: business, visitor_fingerprint: 'a1b2c3d4e5f60003')
        create(:visitor_session, :converted_booking, business: business, visitor_fingerprint: 'a1b2c3d4e5f60004')
        
        # Create page views
        5.times { create(:page_view, business: business) }
      end

      it 'returns correct visitor count' do
        stats = service.quick_stats
        expect(stats[:unique_visitors]).to eq(4)
      end

      it 'returns correct page view count' do
        stats = service.quick_stats
        expect(stats[:page_views]).to eq(5)
      end

      it 'calculates bounce rate' do
        stats = service.quick_stats
        expect(stats[:bounce_rate]).to eq(25.0) # 1 bounce out of 4 sessions
      end

      it 'counts conversions' do
        stats = service.quick_stats
        expect(stats[:conversions]).to eq(1)
      end
    end
  end

  describe '#overview_metrics' do
    it 'returns metrics for specified period' do
      metrics = service.overview_metrics(period: :last_30_days)
      
      expect(metrics).to have_key(:visitors)
      expect(metrics).to have_key(:engagement)
      expect(metrics).to have_key(:conversions)
      expect(metrics).to have_key(:revenue)
      expect(metrics).to have_key(:trend)
      expect(metrics).to have_key(:top_pages)
      expect(metrics).to have_key(:traffic_sources)
    end

    it 'supports different period options' do
      [:today, :last_7_days, :last_30_days, :last_90_days].each do |period|
        expect { service.overview_metrics(period: period) }.not_to raise_error
      end
    end
  end

  describe '#period_comparison' do
    it 'compares current and previous periods' do
      comparison = service.period_comparison(period: :last_30_days)
      
      expect(comparison[:visitors]).to include(:value, :direction, :percentage)
      expect(comparison[:page_views]).to include(:value, :direction, :percentage)
      expect(comparison[:sessions]).to include(:value, :direction, :percentage)
    end

    it 'calculates direction correctly' do
      # Create data in current period
      2.times { create(:visitor_session, business: business, session_start: 1.day.ago) }
      
      # Create data in previous period
      1.times { create(:visitor_session, business: business, session_start: 40.days.ago) }
      
      comparison = service.period_comparison(period: :last_30_days)
      
      # More sessions in current period = 'up' direction
      expect(comparison[:sessions][:direction]).to eq('up')
    end
  end
end

