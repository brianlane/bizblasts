require 'rails_helper'

RSpec.describe DailyActiveUsersService, type: :service do
  let(:business) { create(:business) }
  let(:today) { Date.current }
  let(:yesterday) { 1.day.ago.to_date }
  let(:last_week) { 7.days.ago.to_date }
  
  describe '.today' do
    it 'returns count of users who signed in today' do
      # Create users with different login times
      create(:user, last_sign_in_at: today.beginning_of_day + 2.hours, active: true)
      create(:user, last_sign_in_at: today.end_of_day - 1.hour, active: true)
      create(:user, last_sign_in_at: yesterday.beginning_of_day, active: true)
      create(:user, last_sign_in_at: nil, active: true) # Never logged in
      create(:user, last_sign_in_at: today.beginning_of_day + 1.hour, active: false) # Inactive
      
      expect(DailyActiveUsersService.today).to eq(2)
    end
    
    it 'filters by business when business_id is provided' do
      other_business = create(:business)
      
      create(:user, last_sign_in_at: today.beginning_of_day, business: business, active: true)
      create(:user, last_sign_in_at: today.beginning_of_day, business: other_business, active: true)
      
      expect(DailyActiveUsersService.today(business_id: business.id)).to eq(1)
    end
  end
  
  describe '.yesterday' do
    it 'returns count of users who signed in yesterday' do
      create(:user, last_sign_in_at: yesterday.beginning_of_day + 2.hours, active: true)
      create(:user, last_sign_in_at: yesterday.end_of_day - 1.hour, active: true)
      create(:user, last_sign_in_at: today.beginning_of_day, active: true)
      
      expect(DailyActiveUsersService.yesterday).to eq(2)
    end
  end
  
  describe '.weekly_active_users' do
    it 'returns count of users who signed in within the last 7 days' do
      # Users within the last week
      create(:user, last_sign_in_at: 2.days.ago, active: true)
      create(:user, last_sign_in_at: 5.days.ago, active: true)
      create(:user, last_sign_in_at: 6.days.ago, active: true)
      
      # Users outside the last week
      create(:user, last_sign_in_at: 8.days.ago, active: true)
      create(:user, last_sign_in_at: 10.days.ago, active: true)
      
      expect(DailyActiveUsersService.weekly_active_users).to eq(3)
    end
  end
  
  describe '.monthly_active_users' do
    it 'returns count of users who signed in within the last 30 days' do
      # Users within the last month
      create(:user, last_sign_in_at: 5.days.ago, active: true)
      create(:user, last_sign_in_at: 15.days.ago, active: true)
      create(:user, last_sign_in_at: 29.days.ago, active: true)
      
      # Users outside the last month
      create(:user, last_sign_in_at: 35.days.ago, active: true)
      create(:user, last_sign_in_at: 45.days.ago, active: true)
      
      expect(DailyActiveUsersService.monthly_active_users).to eq(3)
    end
  end
  
  describe '.calculate' do
    let(:start_date) { 3.days.ago.to_date }
    let(:end_date) { today }
    
    it 'returns daily active user counts for date range' do
      # Create users with different sign in dates
      create(:user, last_sign_in_at: 3.days.ago.beginning_of_day, active: true)
      create(:user, last_sign_in_at: 3.days.ago.end_of_day, active: true)
      create(:user, last_sign_in_at: 2.days.ago.beginning_of_day, active: true)
      create(:user, last_sign_in_at: today.beginning_of_day, active: true)
      create(:user, last_sign_in_at: 5.days.ago, active: true) # Outside range
      
      result = DailyActiveUsersService.calculate(start_date: start_date, end_date: end_date)
      
      expect(result[3.days.ago.to_date]).to eq(2)
      expect(result[2.days.ago.to_date]).to eq(1)
      expect(result[1.day.ago.to_date]).to eq(0) # No users this day
      expect(result[today]).to eq(1)
    end
    
    it 'fills in missing dates with zero counts' do
      # Only create user for one day
      create(:user, last_sign_in_at: 2.days.ago.beginning_of_day, active: true)
      
      result = DailyActiveUsersService.calculate(start_date: start_date, end_date: end_date)
      
      expect(result.keys.length).to eq(4) # 4 days in range
      expect(result[3.days.ago.to_date]).to eq(0)
      expect(result[2.days.ago.to_date]).to eq(1)
      expect(result[1.day.ago.to_date]).to eq(0)
      expect(result[today]).to eq(0)
    end
  end
  
  describe '.activity_by_role' do
    it 'returns user activity counts grouped by role' do
      # Create users with different roles who signed in within the last 30 days
      create(:user, role: :client, last_sign_in_at: 5.days.ago, active: true)
      create(:user, role: :client, last_sign_in_at: 10.days.ago, active: true)
      create(:user, role: :manager, last_sign_in_at: 3.days.ago, active: true, business: business)
      create(:user, role: :staff, last_sign_in_at: 7.days.ago, active: true, business: business)
      
      # User who signed in too long ago
      create(:user, role: :client, last_sign_in_at: 40.days.ago, active: true)
      
      result = DailyActiveUsersService.activity_by_role
      
      expect(result['client']).to eq(2)
      expect(result['manager']).to eq(1)
      expect(result['staff']).to eq(1)
    end
  end
  
  describe '.engagement_metrics' do
    context 'when there are no users' do
      it 'returns empty state metrics' do
        metrics = DailyActiveUsersService.engagement_metrics
        
        expect(metrics).to eq({
          total_users: 0,
          daily_active: 0,
          weekly_active: 0,
          monthly_active: 0,
          daily_engagement_rate: 0.0,
          weekly_engagement_rate: 0.0,
          monthly_engagement_rate: 0.0
        })
      end
    end
    
    context 'when there are users' do
      before do
        # Create various users with different activity levels
        create(:user, last_sign_in_at: today.beginning_of_day, active: true) # Today
        create(:user, last_sign_in_at: 3.days.ago, active: true) # Weekly
        create(:user, last_sign_in_at: 15.days.ago, active: true) # Monthly
        create(:user, last_sign_in_at: 45.days.ago, active: true) # Inactive
        create(:user, last_sign_in_at: nil, active: true) # Never logged in
      end
      
      it 'calculates engagement metrics correctly' do
        metrics = DailyActiveUsersService.engagement_metrics
        
        expect(metrics[:total_users]).to eq(5)
        expect(metrics[:daily_active]).to eq(1)
        expect(metrics[:weekly_active]).to eq(2) # Today + 3 days ago
        expect(metrics[:monthly_active]).to eq(3) # Today + 3 days ago + 15 days ago
        expect(metrics[:daily_engagement_rate]).to eq(20.0) # 1/5 * 100
        expect(metrics[:weekly_engagement_rate]).to eq(40.0) # 2/5 * 100
        expect(metrics[:monthly_engagement_rate]).to eq(60.0) # 3/5 * 100
      end
    end
  end
  
  describe '.recent_active_users' do
    it 'returns most recent active users ordered by last sign in' do
      # Create users with different last sign in times
      user1 = create(:user, last_sign_in_at: 1.day.ago, active: true)
      user2 = create(:user, last_sign_in_at: 3.days.ago, active: true)
      user3 = create(:user, last_sign_in_at: 5.days.ago, active: true)
      create(:user, last_sign_in_at: nil, active: true) # Never logged in, should be excluded
      
      result = DailyActiveUsersService.recent_active_users(limit: 2)
      
      expect(result.length).to eq(2)
      expect(result.first).to eq(user1)
      expect(result.second).to eq(user2)
    end
  end
  
  describe '.average_over_period' do
    it 'calculates average daily active users over specified period' do
      # Create users for different days within the 3-day period  
      create(:user, last_sign_in_at: 2.days.ago.beginning_of_day, active: true) # Day 1: 1 user
      create(:user, last_sign_in_at: 1.day.ago.beginning_of_day, active: true) # Day 2: 1 user
      create(:user, last_sign_in_at: 1.day.ago.end_of_day, active: true) # Day 2: 2nd user
      # Day 3 (today) has 0 users
      
      result = DailyActiveUsersService.average_over_period(days: 3)
      
      # The service includes an extra day in the range calculation
      # Average = (1 + 2 + 0) / 4 = 0.75 (includes today + 3 past days = 4 days total)
      expect(result).to eq(0.75)
    end
    
    it 'returns 0 when there are no days' do
      result = DailyActiveUsersService.average_over_period(days: 0)
      expect(result).to eq(0)
    end
  end
  
  describe 'business filtering' do
    let(:business1) { create(:business) }
    let(:business2) { create(:business) }
    
    it 'filters users by business association' do
      # Business users (direct business association)
      create(:user, business: business1, last_sign_in_at: today.beginning_of_day, active: true)
      create(:user, business: business2, last_sign_in_at: today.beginning_of_day, active: true)
      
      # Client users (through client_businesses association)
      client = create(:user, role: :client, last_sign_in_at: today.beginning_of_day, active: true)
      create(:client_business, user: client, business: business1)
      
      expect(DailyActiveUsersService.today(business_id: business1.id)).to eq(2)
      expect(DailyActiveUsersService.today(business_id: business2.id)).to eq(1)
    end
  end
end 