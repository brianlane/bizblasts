# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::ExportService, type: :service do
  let(:business) { create(:business) }
  let(:service) { described_class.new(business) }

  describe '#export' do
    context 'with invalid format' do
      it 'raises ArgumentError' do
        expect do
          service.export(type: :sessions, start_date: 30.days.ago.to_date, end_date: Date.current, format: 'invalid')
        end.to raise_error(ArgumentError, /Invalid format/)
      end
    end

    context 'with invalid export type' do
      it 'raises ArgumentError' do
        expect do
          service.export(type: :invalid_type, start_date: 30.days.ago.to_date, end_date: Date.current)
        end.to raise_error(ArgumentError, /Invalid export type/)
      end
    end

    context 'sessions export' do
      let!(:session) do
        create(:visitor_session,
               business: business,
               session_start: 5.days.ago,
               duration_seconds: 300,
               page_view_count: 5,
               is_bounce: false,
               converted: true,
               conversion_type: 'booking',
               conversion_value: 100)
      end

      it 'exports sessions in CSV format' do
        result = service.export(type: :sessions, start_date: 30.days.ago.to_date, end_date: Date.current, format: 'csv')

        expect(result[:content_type]).to eq('text/csv')
        expect(result[:filename]).to match(/sessions_export_.*\.csv/)
        expect(result[:data]).to include('session_id')
        expect(result[:data]).to include(session.session_id)
      end

      it 'exports sessions in JSON format' do
        result = service.export(type: :sessions, start_date: 30.days.ago.to_date, end_date: Date.current, format: 'json')

        expect(result[:content_type]).to eq('application/json')
        expect(result[:filename]).to match(/sessions_export_.*\.json/)

        json_data = JSON.parse(result[:data])
        expect(json_data['type']).to eq('sessions')
        expect(json_data['record_count']).to eq(1)
        expect(json_data['records'].first['session_id']).to eq(session.session_id)
      end
    end

    context 'page_views export' do
      let!(:page_view) do
        create(:page_view,
               business: business,
               page_path: '/services',
               page_type: 'services',
               created_at: 5.days.ago)
      end

      it 'exports page views in CSV format' do
        result = service.export(type: :page_views, start_date: 30.days.ago.to_date, end_date: Date.current)

        expect(result[:content_type]).to eq('text/csv')
        expect(result[:data]).to include('page_path')
        expect(result[:data]).to include('/services')
      end
    end

    context 'clicks export' do
      let!(:click_event) do
        create(:click_event,
               business: business,
               element_type: 'button',
               element_text: 'Book Now',
               category: 'booking',
               created_at: 5.days.ago)
      end

      it 'exports clicks in CSV format' do
        result = service.export(type: :clicks, start_date: 30.days.ago.to_date, end_date: Date.current)

        expect(result[:content_type]).to eq('text/csv')
        expect(result[:data]).to include('element_type')
        expect(result[:data]).to include('button')
        expect(result[:data]).to include('Book Now')
      end
    end

    context 'conversions export' do
      let!(:converted_session) do
        create(:visitor_session,
               business: business,
               converted: true,
               conversion_type: 'booking',
               conversion_value: 150,
               conversion_time: 5.days.ago)
      end

      it 'exports only converted sessions' do
        create(:visitor_session, business: business, converted: false, session_start: 5.days.ago)

        result = service.export(type: :conversions, start_date: 30.days.ago.to_date, end_date: Date.current)

        expect(result[:content_type]).to eq('text/csv')
        expect(result[:data]).to include('conversion_type')
        expect(result[:data]).to include('booking')
        # Should only have 1 conversion (header + 1 data row)
        expect(result[:data].lines.count).to eq(2)
      end
    end

    context 'summary export' do
      before do
        create(:visitor_session, business: business, session_start: 2.days.ago, converted: false)
        create(:visitor_session, business: business, session_start: 2.days.ago, converted: true,
               conversion_type: 'booking', conversion_value: 100,
               conversion_time: 2.days.ago)
        create(:page_view, business: business, created_at: 2.days.ago)
        create(:click_event, business: business, created_at: 2.days.ago)
      end

      it 'exports daily summary in CSV format' do
        result = service.export(type: :summary, start_date: 3.days.ago.to_date, end_date: Date.current)

        expect(result[:content_type]).to eq('text/csv')
        expect(result[:data]).to include('date')
        expect(result[:data]).to include('unique_visitors')
        expect(result[:data]).to include('total_sessions')
        expect(result[:data]).to include('bounce_rate')
        expect(result[:data]).to include('conversion_rate')
      end

      it 'generates one row per day' do
        result = service.export(type: :summary, start_date: 3.days.ago.to_date, end_date: Date.current)

        # 4 days (3 days ago through today) + 1 header row
        expect(result[:data].lines.count).to eq(5)
      end
    end

    context 'empty data' do
      it 'returns empty CSV message when no data' do
        result = service.export(type: :sessions, start_date: 30.days.ago.to_date, end_date: Date.current)

        expect(result[:content_type]).to eq('text/csv')
        expect(result[:data]).to include('No data available')
      end
    end
  end

  describe '.available_export_types' do
    it 'returns expected export types' do
      types = described_class.available_export_types

      expect(types).to include('sessions')
      expect(types).to include('page_views')
      expect(types).to include('clicks')
      expect(types).to include('conversions')
      expect(types).to include('summary')
    end
  end

  describe 'record limits' do
    it 'limits results to MAX_RECORDS' do
      # Just verify the constant exists and is reasonable
      expect(described_class::MAX_RECORDS).to eq(50_000)
    end
  end

  describe 'tenant scoping' do
    let(:other_business) { create(:business) }
    let!(:my_session) { create(:visitor_session, business: business, session_start: 5.days.ago) }
    let!(:other_session) { create(:visitor_session, business: other_business, session_start: 5.days.ago) }

    it 'only exports data for the specified business' do
      result = service.export(type: :sessions, start_date: 30.days.ago.to_date, end_date: Date.current, format: 'json')

      json_data = JSON.parse(result[:data])
      session_ids = json_data['records'].map { |r| r['session_id'] }

      expect(session_ids).to include(my_session.session_id)
      expect(session_ids).not_to include(other_session.session_id)
    end
  end
end
