# frozen_string_literal: true

class PageView < ApplicationRecord
  include TenantScoped

  belongs_to :business
  belongs_to :page, optional: true
  belongs_to :visitor_session, primary_key: :session_id, foreign_key: :session_id, optional: true

  # Fingerprint format: hexadecimal string, 8-32 characters
  FINGERPRINT_FORMAT = /\A[a-f0-9]{8,32}\z/

  # Validations
  validates :visitor_fingerprint, presence: true,
            format: { with: FINGERPRINT_FORMAT, message: 'must be a valid hexadecimal string (8-32 characters)' }
  validates :session_id, presence: true
  validates :page_path, presence: true

  # Enums
  enum :device_type, { desktop: 'desktop', mobile: 'mobile', tablet: 'tablet' }, prefix: true

  # Scopes
  scope :for_period, ->(start_date, end_date) { where(created_at: start_date.beginning_of_day..end_date.end_of_day) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :last_7_days, -> { where(created_at: 7.days.ago.beginning_of_day..Time.current.end_of_day) }
  scope :last_30_days, -> { where(created_at: 30.days.ago.beginning_of_day..Time.current.end_of_day) }
  scope :last_90_days, -> { where(created_at: 90.days.ago.beginning_of_day..Time.current.end_of_day) }
  
  scope :entry_pages, -> { where(is_entry_page: true) }
  scope :exit_pages, -> { where(is_exit_page: true) }
  scope :bounces, -> { where(is_bounce: true) }
  
  scope :from_referrer, ->(domain) { where(referrer_domain: domain) }
  scope :from_utm_source, ->(source) { where(utm_source: source) }
  scope :on_device, ->(device) { where(device_type: device) }

  # Class methods for analytics
  class << self
    def unique_visitors(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date).distinct.count(:visitor_fingerprint)
    end

    def total_page_views(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date).count
    end

    def bounce_rate(start_date: 30.days.ago, end_date: Time.current)
      total = for_period(start_date, end_date).entry_pages.count
      bounces = for_period(start_date, end_date).bounces.count
      return 0.0 if total.zero?
      (bounces.to_f / total * 100).round(2)
    end

    def top_pages(start_date: 30.days.ago, end_date: Time.current, limit: 10)
      for_period(start_date, end_date)
        .group(:page_path)
        .order('count_all DESC')
        .limit(limit)
        .count
    end

    def top_referrers(start_date: 30.days.ago, end_date: Time.current, limit: 10)
      for_period(start_date, end_date)
        .where.not(referrer_domain: [nil, ''])
        .group(:referrer_domain)
        .order('count_all DESC')
        .limit(limit)
        .count
    end

    def device_breakdown(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .group(:device_type)
        .count
        .transform_values { |v| v }
    end

    def traffic_by_source(start_date: 30.days.ago, end_date: Time.current)
      # Use database aggregation instead of loading all records into memory
      # This is much more efficient for large datasets
      connection = ActiveRecord::Base.connection

      # Build query with proper parameter binding for PostgreSQL
      sql = sanitize_sql_array([<<-SQL, start_date.beginning_of_day, end_date.end_of_day])
        SELECT
          CASE
            WHEN LOWER(utm_medium) IN ('cpc', 'ppc', 'paid') THEN 'paid'
            WHEN referrer_domain IS NULL OR referrer_domain = '' THEN 'direct'
            WHEN referrer_domain ~* 'google|bing|yahoo|duckduckgo' THEN 'organic'
            WHEN referrer_domain ~* 'facebook|twitter|instagram|linkedin|pinterest|tiktok' THEN 'social'
            ELSE 'referral'
          END as source,
          COUNT(*) as count
        FROM (#{for_period(start_date, end_date).to_sql}) as scoped_page_views
        GROUP BY source
      SQL

      results = connection.exec_query(sql)

      # Initialize with zeros
      traffic = { direct: 0, organic: 0, referral: 0, social: 0, paid: 0 }

      # Fill in actual counts
      results.each do |row|
        traffic[row['source'].to_sym] = row['count']
      end

      traffic
    end

    def daily_trend(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .group("DATE(created_at)")
        .count
        .transform_keys { |k| k.to_date }
    end

    private

    def categorize_traffic_source(page_view)
      return :paid if page_view.utm_medium&.downcase&.in?(%w[cpc ppc paid])
      return :direct if page_view.referrer_domain.blank?
      
      search_engines = %w[google bing yahoo duckduckgo]
      social_networks = %w[facebook twitter instagram linkedin pinterest tiktok]
      
      domain = page_view.referrer_domain.to_s.downcase
      
      return :organic if search_engines.any? { |se| domain.include?(se) }
      return :social if social_networks.any? { |sn| domain.include?(sn) }
      
      :referral
    end
  end

  # Ransack configuration
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id page_id visitor_fingerprint session_id page_path page_type
       referrer_domain utm_source utm_medium utm_campaign device_type browser os
       country region city time_on_page is_entry_page is_exit_page is_bounce created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business page visitor_session]
  end
end

