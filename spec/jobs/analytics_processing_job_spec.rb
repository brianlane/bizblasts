# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalyticsProcessingJob, type: :job do
  include ActiveJob::TestHelper

  let!(:tenant1) { create(:business) }
  let!(:tenant2) { create(:business) }
  
  let!(:staff1) { create(:staff_member, business: tenant1) }
  let!(:customer1) { create(:tenant_customer, business: tenant1) }
  let!(:service1) { create(:service, business: tenant1) }
  
  let!(:staff2) { create(:staff_member, business: tenant2) }
  let!(:customer2) { create(:tenant_customer, business: tenant2) }
  let!(:service2) { create(:service, business: tenant2) }

  # Create some bookings in different tenants and with different statuses
  let!(:booking1_t1_completed) { 
    create(:booking, business: tenant1, staff_member: staff1, service: service1, tenant_customer: customer1, 
           start_time: 10.days.ago, end_time: 10.days.ago + 1.hour, status: :completed)
  }
  let!(:booking2_t1_cancelled) { 
    create(:booking, business: tenant1, staff_member: staff1, service: service1, tenant_customer: customer1, 
           start_time: 5.days.ago, end_time: 5.days.ago + 1.hour, status: :cancelled)
  }
   let!(:booking3_t1_pending) { 
    create(:booking, business: tenant1, staff_member: staff1, service: service1, tenant_customer: customer1, 
           start_time: 2.days.ago, end_time: 2.days.ago + 1.hour, status: :pending)
  }
  let!(:booking4_t2_completed) { 
    create(:booking, business: tenant2, staff_member: staff2, service: service2, tenant_customer: customer2, 
           start_time: 12.days.ago, end_time: 12.days.ago + 1.hour, status: :completed)
  }
  
  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  describe '#perform' do
    context 'with report_type: booking_summary' do
      context 'without tenant_id (global)' do
        it 'processes booking summary for all tenants' do
          # Need to allow logger info messages for inspection
          allow(Rails.logger).to receive(:info)
          
          # Execute job directly for simplicity, could also use perform_enqueued_jobs
          result = described_class.new.perform('booking_summary') 
          
          expect(Rails.logger).to have_received(:info).with(/Booking Summary Report:/)
          # Check aggregated results (across both tenants)
          expect(result[:total_bookings]).to eq(4) 
          expect(result[:completed_bookings]).to eq(2) # One from each tenant
          expect(result[:cancelled_bookings]).to eq(1) 
          expect(result[:no_show_bookings]).to eq(0) 
          # Add more specific checks if needed (e.g., rates)
        end
      end

      context 'with tenant_id' do
        it 'processes booking summary scoped to the tenant' do
          allow(Rails.logger).to receive(:info)

          result = described_class.new.perform('booking_summary', tenant1.id)

          expect(Rails.logger).to have_received(:info).with(/Booking Summary Report:/)
          # Check results scoped to tenant1
          expect(result[:total_bookings]).to eq(3) # Only tenant1 bookings
          expect(result[:completed_bookings]).to eq(1)
          expect(result[:cancelled_bookings]).to eq(1)
          expect(result[:no_show_bookings]).to eq(0)
        end
      end
    end
    
    context 'with unknown report_type' do
      it 'logs an error' do
        allow(Rails.logger).to receive(:error)
        described_class.new.perform('invalid_report')
        expect(Rails.logger).to have_received(:error).with("Unknown report type: invalid_report")
      end
    end

    # TODO: Add contexts for other report types: 
    # revenue_summary, marketing_summary, customer_retention, staff_performance
  end
end 