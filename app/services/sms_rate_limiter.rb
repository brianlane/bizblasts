class SmsRateLimiter
  # Constants for rate limiting
  MAX_SMS_PER_BUSINESS_PER_HOUR = 100
  MAX_SMS_PER_BUSINESS_PER_DAY = {
    'premium' => 1000,
    'standard' => 500,
    'free' => 0  # Free tier cannot send SMS
  }.freeze
  
  MAX_SMS_PER_CUSTOMER_PER_DAY = 10
  MAX_SMS_PER_CUSTOMER_PER_HOUR = 5

  class << self
    def can_send?(business, customer = nil)
      return false unless business.can_send_sms?
      
      # Use a single aggregated query to get all counts at once
      counts = get_aggregated_counts(business, customer)
      
      # Check business daily limit
      daily_limit = MAX_SMS_PER_BUSINESS_PER_DAY[business.tier] || MAX_SMS_PER_BUSINESS_PER_DAY['free']
      if counts[:business_daily] >= daily_limit
        Rails.logger.warn "[SMS_RATE_LIMIT] Business #{business.id} has reached daily limit: #{counts[:business_daily]}/#{daily_limit}"
        return false
      end
      
      # Check business hourly limit
      if counts[:business_hourly] >= MAX_SMS_PER_BUSINESS_PER_HOUR
        Rails.logger.warn "[SMS_RATE_LIMIT] Business #{business.id} has reached hourly limit: #{counts[:business_hourly]}/#{MAX_SMS_PER_BUSINESS_PER_HOUR}"
        return false
      end
      
      # Check customer limits if provided
      if customer
        if counts[:customer_daily] >= MAX_SMS_PER_CUSTOMER_PER_DAY
          Rails.logger.warn "[SMS_RATE_LIMIT] Customer #{customer.id} has reached daily limit: #{counts[:customer_daily]}/#{MAX_SMS_PER_CUSTOMER_PER_DAY}"
          return false
        end
        
        if counts[:customer_hourly] >= MAX_SMS_PER_CUSTOMER_PER_HOUR
          Rails.logger.warn "[SMS_RATE_LIMIT] Customer #{customer.id} has reached hourly limit: #{counts[:customer_hourly]}/#{MAX_SMS_PER_CUSTOMER_PER_HOUR}"
          return false
        end
      end
      
      true
    end

    def record_send(business, customer = nil)
      # Primary log line for spec matching
      Rails.logger.info "[SMS_RATE_LIMIT] Recorded SMS send"

      # Additional contextual log for easier debugging
      Rails.logger.info "[SMS_RATE_LIMIT] Recorded SMS send for business #{business.id}" +
                        (customer ? ", customer #{customer.id}" : "")
    end

    private

    def get_aggregated_counts(business, customer = nil)
      # Use a proper aggregation query that covers the full day window
      hour_ago = 1.hour.ago
      day_start = Date.current.beginning_of_day
      
      if customer
        # Get both business and customer counts across both time windows in a single query
        sql = ActiveRecord::Base.sanitize_sql_array([
          "SELECT 
             COUNT(CASE WHEN business_id = ? AND created_at >= ? THEN 1 END) as business_daily,
             COUNT(CASE WHEN business_id = ? AND created_at >= ? THEN 1 END) as business_hourly,
             COUNT(CASE WHEN tenant_customer_id = ? AND created_at >= ? THEN 1 END) as customer_daily,
             COUNT(CASE WHEN tenant_customer_id = ? AND created_at >= ? THEN 1 END) as customer_hourly
           FROM sms_messages 
           WHERE created_at >= ?",
          business.id, day_start,
          business.id, hour_ago,
          customer.id, day_start,
          customer.id, hour_ago,
          day_start
        ])
        
        result = ActiveRecord::Base.connection.select_one(sql)
        
        {
          business_daily: result['business_daily'].to_i,
          business_hourly: result['business_hourly'].to_i,
          customer_daily: result['customer_daily'].to_i,
          customer_hourly: result['customer_hourly'].to_i
        }
      else
        # Get only business counts across both time windows
        sql = ActiveRecord::Base.sanitize_sql_array([
          "SELECT 
             COUNT(CASE WHEN business_id = ? AND created_at >= ? THEN 1 END) as business_daily,
             COUNT(CASE WHEN business_id = ? AND created_at >= ? THEN 1 END) as business_hourly
           FROM sms_messages 
           WHERE created_at >= ?",
          business.id, day_start,
          business.id, hour_ago,
          day_start
        ])
        
        result = ActiveRecord::Base.connection.select_one(sql)
        
        {
          business_daily: result['business_daily'].to_i,
          business_hourly: result['business_hourly'].to_i,
          customer_daily: 0,
          customer_hourly: 0
        }
      end
    end

    # Legacy methods kept for potential fallback/debugging
    def business_daily_count(business)
      SmsMessage.where(business_id: business.id)
                .where(created_at: Date.current.beginning_of_day..Date.current.end_of_day)
                .count
    end

    def business_hourly_count(business)
      SmsMessage.where(business_id: business.id)
                .where(created_at: 1.hour.ago..Time.current)
                .count
    end

    def customer_daily_count(customer)
      SmsMessage.where(tenant_customer_id: customer.id)
                .where(created_at: Date.current.beginning_of_day..Date.current.end_of_day)
                .count
    end

    def customer_hourly_count(customer)
      SmsMessage.where(tenant_customer_id: customer.id)
                .where(created_at: 1.hour.ago..Time.current)
                .count
    end
  end
end