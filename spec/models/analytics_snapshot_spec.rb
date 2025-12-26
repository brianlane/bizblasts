# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalyticsSnapshot, type: :model do
  let(:business) { create(:business) }

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'validations' do
    it 'requires snapshot_type to be valid' do
      snapshot = build(:analytics_snapshot, business: business, snapshot_type: 'invalid')
      expect(snapshot).not_to be_valid
    end

    it 'requires period_start' do
      snapshot = build(:analytics_snapshot, business: business, period_start: nil)
      expect(snapshot).not_to be_valid
    end

    it 'validates period_end after period_start' do
      snapshot = build(:analytics_snapshot, business: business, 
                       period_start: Date.current, period_end: Date.yesterday)
      expect(snapshot).not_to be_valid
    end

    it 'enforces unique period for business/type combination' do
      create(:analytics_snapshot, business: business, snapshot_type: 'daily',
             period_start: Date.current, period_end: Date.current)
      
      duplicate = build(:analytics_snapshot, business: business, snapshot_type: 'daily',
                        period_start: Date.current, period_end: Date.current)
      # The uniqueness is enforced at the database level, so we need to try to save
      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'scopes' do
    before do
      create(:analytics_snapshot, :daily, business: business)
      create(:analytics_snapshot, :weekly, business: business)
      create(:analytics_snapshot, :monthly, business: business)
    end

    it 'filters by snapshot type' do
      expect(AnalyticsSnapshot.daily.count).to eq(1)
      expect(AnalyticsSnapshot.weekly.count).to eq(1)
      expect(AnalyticsSnapshot.monthly.count).to eq(1)
    end
  end

  describe 'class methods' do
    describe '.aggregate_metrics' do
      before do
        create(:analytics_snapshot, :daily, business: business,
               period_start: 2.days.ago.to_date, period_end: 2.days.ago.to_date,
               unique_visitors: 100, total_page_views: 500)
        create(:analytics_snapshot, :daily, business: business,
               period_start: 1.day.ago.to_date, period_end: 1.day.ago.to_date,
               unique_visitors: 150, total_page_views: 750)
      end

      it 'aggregates metrics for the period' do
        metrics = AnalyticsSnapshot.aggregate_metrics(
          type: 'daily',
          start_date: 5.days.ago.to_date,
          end_date: Date.current
        )
        
        expect(metrics[:unique_visitors]).to eq(250)
        expect(metrics[:total_page_views]).to eq(1250)
      end
    end
  end

  describe 'instance methods' do
    describe '#period_label' do
      it 'formats daily period' do
        snapshot = build(:analytics_snapshot, :daily, period_start: Date.new(2024, 12, 25))
        expect(snapshot.period_label).to eq('Dec 25, 2024')
      end

      it 'formats weekly period' do
        snapshot = build(:analytics_snapshot, :weekly, 
                         period_start: Date.new(2024, 12, 23),
                         period_end: Date.new(2024, 12, 29))
        expect(snapshot.period_label).to include('Dec 23')
        expect(snapshot.period_label).to include('Dec 29')
      end

      it 'formats monthly period' do
        snapshot = build(:analytics_snapshot, :monthly, period_start: Date.new(2024, 12, 1))
        expect(snapshot.period_label).to eq('December 2024')
      end
    end
  end
end

