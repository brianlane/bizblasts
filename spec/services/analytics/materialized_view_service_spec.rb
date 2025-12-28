# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::MaterializedViewService, type: :service do
  let(:business) { create(:business) }
  let(:service) { described_class.new(business) }
  let(:start_date) { 30.days.ago.to_date }
  let(:end_date) { Date.current }

  describe '#views_available?' do
    context 'when views exist' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:data_source_exists?)
          .with('daily_analytics_summaries')
          .and_return(true)
      end

      it 'returns true' do
        expect(service.views_available?).to be true
      end

      it 'caches the result' do
        expect(ActiveRecord::Base.connection).to receive(:data_source_exists?).once
        2.times { service.views_available? }
      end
    end

    context 'when views do not exist' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:data_source_exists?)
          .with('daily_analytics_summaries')
          .and_return(false)
      end

      it 'returns false' do
        expect(service.views_available?).to be false
      end
    end

    context 'when database error occurs' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:data_source_exists?)
          .and_raise(ActiveRecord::StatementInvalid.new("Database error"))
      end

      it 'returns false' do
        expect(service.views_available?).to be false
      end
    end
  end

  describe '#daily_summaries' do
    context 'when views are not available' do
      before do
        allow(service).to receive(:views_available?).and_return(false)
      end

      it 'returns empty array' do
        expect(service.daily_summaries(start_date, end_date)).to eq([])
      end
    end

    context 'when views are available' do
      let(:mock_results) do
        [
          {
            'date' => Date.current,
            'total_sessions' => '100',
            'unique_visitors' => '80',
            'bounced_sessions' => '20',
            'conversions' => '10',
            'total_conversion_value' => '500.00',
            'avg_session_duration' => '180.5',
            'new_visitors' => '60',
            'returning_visitors' => '20'
          }
        ]
      end

      before do
        allow(service).to receive(:views_available?).and_return(true)
        allow(service).to receive(:execute_query).and_return(mock_results)
      end

      it 'returns formatted daily summaries' do
        result = service.daily_summaries(start_date, end_date)

        expect(result).to be_an(Array)
        expect(result.first[:sessions]).to eq(100)
        expect(result.first[:visitors]).to eq(80)
        expect(result.first[:bounced]).to eq(20)
        expect(result.first[:conversions]).to eq(10)
        expect(result.first[:conversion_value]).to eq(500.00)
        expect(result.first[:avg_duration]).to eq(181)
        expect(result.first[:new_visitors]).to eq(60)
        expect(result.first[:returning_visitors]).to eq(20)
      end
    end
  end

  describe '#traffic_sources' do
    context 'when views are not available' do
      before do
        allow(service).to receive(:views_available?).and_return(false)
      end

      it 'returns default traffic sources' do
        result = service.traffic_sources(start_date, end_date)
        expect(result).to eq({ direct: 0, organic: 0, social: 0, referral: 0, paid: 0 })
      end
    end

    context 'when views are available' do
      let(:mock_results) do
        [
          { 'source_type' => 'direct', 'total' => '50' },
          { 'source_type' => 'organic', 'total' => '30' },
          { 'source_type' => 'social', 'total' => '10' },
          { 'source_type' => 'referral', 'total' => '8' },
          { 'source_type' => 'paid', 'total' => '2' }
        ]
      end

      before do
        allow(service).to receive(:views_available?).and_return(true)
        allow(service).to receive(:execute_query).and_return(mock_results)
      end

      it 'returns traffic source counts' do
        result = service.traffic_sources(start_date, end_date)

        expect(result[:direct]).to eq(50)
        expect(result[:organic]).to eq(30)
        expect(result[:social]).to eq(10)
        expect(result[:referral]).to eq(8)
        expect(result[:paid]).to eq(2)
      end
    end
  end

  describe '#top_pages' do
    context 'when views are not available' do
      before do
        allow(service).to receive(:views_available?).and_return(false)
      end

      it 'returns empty array' do
        expect(service.top_pages(start_date, end_date)).to eq([])
      end
    end

    context 'when views are available' do
      let(:mock_results) do
        [
          { 'page_path' => '/services', 'total_views' => '150' },
          { 'page_path' => '/', 'total_views' => '120' },
          { 'page_path' => '/contact', 'total_views' => '50' }
        ]
      end

      before do
        allow(service).to receive(:views_available?).and_return(true)
        allow(service).to receive(:execute_query).and_return(mock_results)
      end

      it 'returns top pages with view counts' do
        result = service.top_pages(start_date, end_date)

        expect(result.length).to eq(3)
        expect(result.first[:path]).to eq('/services')
        expect(result.first[:views]).to eq(150)
      end

      it 'respects limit parameter' do
        expect(service).to receive(:execute_query) do |sql, params|
          expect(params.last).to eq(10)
          mock_results
        end

        service.top_pages(start_date, end_date, limit: 10)
      end
    end
  end

  describe '#period_summary' do
    context 'when views are not available' do
      before do
        allow(service).to receive(:views_available?).and_return(false)
      end

      it 'returns nil' do
        expect(service.period_summary(start_date, end_date)).to be_nil
      end
    end

    context 'when views are available' do
      let(:mock_result) do
        {
          'sessions' => '500',
          'visitors' => '350',
          'bounced' => '100',
          'conversions' => '50',
          'conversion_value' => '2500.00',
          'bounce_rate' => '20.0',
          'conversion_rate' => '10.0',
          'avg_duration' => '185.5'
        }
      end

      before do
        allow(service).to receive(:views_available?).and_return(true)
        allow(service).to receive(:execute_query).and_return([mock_result])
      end

      it 'returns period summary metrics' do
        result = service.period_summary(start_date, end_date)

        expect(result[:sessions]).to eq(500)
        expect(result[:visitors]).to eq(350)
        expect(result[:bounced]).to eq(100)
        expect(result[:conversions]).to eq(50)
        expect(result[:conversion_value]).to eq(2500.00)
        expect(result[:bounce_rate]).to eq(20.0)
        expect(result[:conversion_rate]).to eq(10.0)
        expect(result[:avg_duration]).to eq(186)
      end
    end

    context 'when query returns no results' do
      before do
        allow(service).to receive(:views_available?).and_return(true)
        allow(service).to receive(:execute_query).and_return([])
      end

      it 'returns nil' do
        expect(service.period_summary(start_date, end_date)).to be_nil
      end
    end
  end
end
