class DailyActiveUsersService
  class << self
    # Calculate daily active users for a specific date range
    # Returns a hash with date as key and count as value
    def calculate(start_date: 30.days.ago.to_date, end_date: Date.current, business_id: nil)
      query = base_query(business_id)
      
      # Group by date and count unique users who signed in each day
      daily_counts = query
        .where(last_sign_in_at: start_date.beginning_of_day..end_date.end_of_day)
        .group("DATE(last_sign_in_at)")
        .count
      
      # Fill in missing dates with 0 counts
      date_range = (start_date..end_date)
      result = {}
      
      date_range.each do |date|
        result[date] = daily_counts[date] || 0
      end
      
      result
    end
    
    # Calculate daily active users for today
    def today(business_id: nil)
      query = base_query(business_id)
      
      query.where(last_sign_in_at: Date.current.beginning_of_day..Date.current.end_of_day).count
    end
    
    # Calculate daily active users for yesterday
    def yesterday(business_id: nil)
      query = base_query(business_id)
      yesterday_date = 1.day.ago.to_date
      
      query.where(last_sign_in_at: yesterday_date.beginning_of_day..yesterday_date.end_of_day).count
    end
    
    # Calculate average daily active users over a period
    def average_over_period(days: 30, business_id: nil)
      end_date = Date.current
      start_date = days.days.ago.to_date
      
      daily_counts = calculate(start_date: start_date, end_date: end_date, business_id: business_id)
      total_days = daily_counts.keys.count
      
      return 0 if total_days.zero?
      
      total_active_users = daily_counts.values.sum
      (total_active_users.to_f / total_days).round(2)
    end
    
    # Get weekly active users (users who logged in within the last 7 days)
    def weekly_active_users(business_id: nil)
      query = base_query(business_id)
      
      query.where(last_sign_in_at: 7.days.ago.beginning_of_day..Time.current).count
    end
    
    # Get monthly active users (users who logged in within the last 30 days)
    def monthly_active_users(business_id: nil)
      query = base_query(business_id)
      
      query.where(last_sign_in_at: 30.days.ago.beginning_of_day..Time.current).count
    end
    
    # Get user activity breakdown by role
    def activity_by_role(start_date: 30.days.ago.to_date, end_date: Date.current, business_id: nil)
      query = base_query(business_id)
      
      query
        .where(last_sign_in_at: start_date.beginning_of_day..end_date.end_of_day)
        .group(:role)
        .count
    end
    
    # Get most recent active users
    def recent_active_users(limit: 10, business_id: nil)
      query = base_query(business_id)
      
      query
        .where.not(last_sign_in_at: nil)
        .order(last_sign_in_at: :desc)
        .limit(limit)
    end
    
    # Get engagement metrics
    def engagement_metrics(business_id: nil)
      query = base_query(business_id)
      total_users = query.count
      
      return engagement_empty_state if total_users.zero?
      
      today_active = today(business_id: business_id)
      weekly_active = weekly_active_users(business_id: business_id)
      monthly_active = monthly_active_users(business_id: business_id)
      
      {
        total_users: total_users,
        daily_active: today_active,
        weekly_active: weekly_active,
        monthly_active: monthly_active,
        daily_engagement_rate: calculate_percentage(today_active, total_users),
        weekly_engagement_rate: calculate_percentage(weekly_active, total_users),
        monthly_engagement_rate: calculate_percentage(monthly_active, total_users)
      }
    end
    
    private
    
    def base_query(business_id)
      query = User.where(active: true)
      
      if business_id.present?
        # For business-specific queries, include users associated with that business
        # Use a subquery to combine business users and client users for that business
        business_user_ids = User.where(business_id: business_id).pluck(:id)
        client_user_ids = User.joins(:client_businesses)
                             .where(client_businesses: { business_id: business_id })
                             .pluck(:id)
        
        all_user_ids = (business_user_ids + client_user_ids).uniq
        query = query.where(id: all_user_ids)
      end
      
      query
    end
    
    def calculate_percentage(numerator, denominator)
      return 0.0 if denominator.zero?
      
      ((numerator.to_f / denominator) * 100).round(2)
    end
    
    def engagement_empty_state
      {
        total_users: 0,
        daily_active: 0,
        weekly_active: 0,
        monthly_active: 0,
        daily_engagement_rate: 0.0,
        weekly_engagement_rate: 0.0,
        monthly_engagement_rate: 0.0
      }
    end
  end
end 