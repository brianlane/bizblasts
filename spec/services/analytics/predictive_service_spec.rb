# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::PredictiveService, type: :service do
  let(:business) { create(:business) }
  let(:service) { described_class.new(business) }

  describe '#forecast_service_demand' do
    let(:bookable_service) { create(:service, business: business, price: 100) }

    context 'with sufficient historical data' do
      before do
        # Create 60 days of historical bookings
        60.times do |i|
          create(:booking,
                 business: business,
                 service: bookable_service,
                 created_at: i.days.ago,
                 start_time: i.days.ago + 2.hours)
        end
      end

      it 'returns forecast with confidence level' do
        result = service.forecast_service_demand(bookable_service.id, 7)

        expect(result[:service_id]).to eq(bookable_service.id)
        expect(result[:service_name]).to eq(bookable_service.name)
        expect(result[:historical_avg]).to be_a(Numeric)
        expect(result[:trend_direction]).to be_in(['increasing', 'decreasing', 'stable'])
        expect(result[:forecast]).to be_an(Array)
        expect(result[:forecast].size).to eq(7)

        forecast_day = result[:forecast].first
        expect(forecast_day).to include(:date, :forecasted_bookings, :confidence_level)
        expect(forecast_day[:forecasted_bookings]).to be >= 1
      end
    end

    context 'with insufficient historical data' do
      before do
        # Only 3 days of data
        create_list(:booking, 3,
                    business: business,
                    service: bookable_service,
                    created_at: 2.days.ago)
      end

      it 'returns error for insufficient data' do
        result = service.forecast_service_demand(bookable_service.id)

        expect(result[:error]).to eq('Insufficient historical data')
      end
    end

    context 'with non-existent service' do
      it 'returns error for missing service' do
        result = service.forecast_service_demand(99999)

        expect(result[:error]).to eq('Service not found')
      end
    end
  end

  describe '#optimal_pricing_recommendations' do
    let(:bookable_service) { create(:service, business: business, price: 100) }

    before do
      create_list(:booking, 30,
                  business: business,
                  service: bookable_service,
                  created_at: 15.days.ago)
    end

    it 'generates pricing scenarios' do
      result = service.optimal_pricing_recommendations(bookable_service.id)

      expect(result[:service_id]).to eq(bookable_service.id)
      expect(result[:current_price]).to eq(100)
      expect(result[:optimal_price]).to be_a(Numeric)
      expect(result[:scenarios]).to be_an(Array)

      scenario = result[:scenarios].first
      expect(scenario).to include(
        :price_change,
        :new_price,
        :estimated_monthly_bookings,
        :estimated_monthly_revenue,
        :revenue_change
      )
    end

    it 'handles service not found' do
      result = service.optimal_pricing_recommendations(99999)
      expect(result[:error]).to eq('Service not found')
    end
  end

  describe '#detect_anomalies' do
    before do
      ActsAsTenant.with_tenant(business) do
        # Create normal booking pattern
        25.times do |i|
          create(:booking,
                 business: business,
                 created_at: (30 - i).days.ago,
                 start_time: (30 - i).days.ago + 10.hours)
        end

        # Create anomaly - spike
        10.times do
          create(:booking,
                 business: business,
                 created_at: 2.days.ago,
                 start_time: 2.days.ago + 10.hours)
        end
      end
    end

    it 'detects booking anomalies' do
      result = service.detect_anomalies(:bookings, 30.days)

      expect(result).to be_an(Array)
      anomaly = result.first
      expect(anomaly).to include(:date, :metric, :value, :expected_range, :severity, :deviation_percentage)
      expect(anomaly[:severity]).to be_in(['low', 'medium', 'high', 'critical'])
      expect(anomaly[:direction]).to be_in(['above', 'below'])
    end

    it 'returns empty array for unknown metric type' do
      result = service.detect_anomalies(:unknown_metric)
      expect(result).to eq([])
    end
  end

  describe '#predict_next_purchase' do
    let(:customer) { create(:tenant_customer, business: business) }

    context 'with purchase history' do
      before do
        # Create purchase pattern: 30 days apart
        [90, 60, 30].each do |days_ago|
          create(:booking,
                 business: business,
                 tenant_customer: customer,
                 created_at: days_ago.days.ago)
        end
      end

      it 'predicts next purchase date' do
        result = service.predict_next_purchase(customer)

        expect(result[:customer_id]).to eq(customer.id)
        expect(result[:avg_interval_days]).to be_within(5).of(30)
        expect(result[:predicted_next_purchase]).to be_a(Time)
        expect(result[:confidence]).to be_in(['low', 'medium', 'high'])
      end
    end

    context 'with insufficient purchase history' do
      before do
        create(:booking, business: business, tenant_customer: customer)
      end

      it 'returns nil for single purchase' do
        result = service.predict_next_purchase(customer)
        expect(result).to be_nil
      end
    end
  end

  describe '#optimize_staff_scheduling' do
    let(:staff_member) { create(:staff_member, business: business) }

    before do
      # Create historical booking pattern
      20.times do |i|
        day_offset = i * 7 # Same day of week
        create(:booking,
               business: business,
               staff_member: staff_member,
               created_at: day_offset.days.ago,
               start_time: day_offset.days.ago.change(hour: 10))
      end
    end

    it 'provides scheduling recommendations' do
      result = service.optimize_staff_scheduling(Date.current)

      expect(result[:date]).to be_a(Date)
      expect(result[:day_of_week]).to be_present
      expect(result[:recommendations]).to be_an(Array)

      if result[:recommendations].any?
        hour_recommendation = result[:recommendations].first
        expect(hour_recommendation).to include(:hour, :expected_bookings, :recommended_staff)
      end
    end
  end
end
