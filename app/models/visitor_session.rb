# frozen_string_literal: true

class VisitorSession < ApplicationRecord
  include TenantScoped

  belongs_to :business
  has_many :page_views, primary_key: :session_id, foreign_key: :session_id, dependent: :nullify
  has_many :click_events, primary_key: :session_id, foreign_key: :session_id, dependent: :nullify

  # Validations
  validates :visitor_fingerprint, presence: true
  validates :session_id, presence: true, uniqueness: true
  validates :session_start, presence: true

  # Scopes
  scope :for_period, ->(start_date, end_date) { where(session_start: start_date.beginning_of_day..end_date.end_of_day) }
  scope :today, -> { where(session_start: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :last_7_days, -> { where(session_start: 7.days.ago.beginning_of_day..Time.current.end_of_day) }
  scope :last_30_days, -> { where(session_start: 30.days.ago.beginning_of_day..Time.current.end_of_day) }
  scope :last_90_days, -> { where(session_start: 90.days.ago.beginning_of_day..Time.current.end_of_day) }
  
  scope :bounced, -> { where(is_bounce: true) }
  scope :engaged, -> { where(is_bounce: false) }
  scope :converted, -> { where(converted: true) }
  scope :returning_visitors, -> { where(is_returning_visitor: true) }
  scope :new_visitors, -> { where(is_returning_visitor: false) }
  scope :active, -> { where(session_end: nil).or(where('session_end > ?', 30.minutes.ago)) }

  # Callbacks
  before_validation :set_session_start, on: :create

  # Class methods for analytics
  class << self
    def total_sessions(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date).count
    end

    def unique_visitors(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date).distinct.count(:visitor_fingerprint)
    end

    def bounce_rate(start_date: 30.days.ago, end_date: Time.current)
      total = total_sessions(start_date: start_date, end_date: end_date)
      return 0.0 if total.zero?
      (for_period(start_date, end_date).bounced.count.to_f / total * 100).round(2)
    end

    def average_session_duration(start_date: 30.days.ago, end_date: Time.current)
      avg = for_period(start_date, end_date)
        .where.not(duration_seconds: nil)
        .where('duration_seconds > 0')
        .average(:duration_seconds)
      avg&.round(0) || 0
    end

    def average_pages_per_session(start_date: 30.days.ago, end_date: Time.current)
      avg = for_period(start_date, end_date).average(:page_view_count)
      avg&.round(2) || 0.0
    end

    def conversion_rate(start_date: 30.days.ago, end_date: Time.current)
      total = total_sessions(start_date: start_date, end_date: end_date)
      return 0.0 if total.zero?
      (for_period(start_date, end_date).converted.count.to_f / total * 100).round(2)
    end

    def conversions_by_type(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .converted
        .group(:conversion_type)
        .count
    end

    def total_conversion_value(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date).converted.sum(:conversion_value)
    end

    def new_vs_returning(start_date: 30.days.ago, end_date: Time.current)
      sessions = for_period(start_date, end_date)
      {
        new: sessions.new_visitors.count,
        returning: sessions.returning_visitors.count
      }
    end

    def traffic_sources(start_date: 30.days.ago, end_date: Time.current)
      result = { direct: 0, organic: 0, referral: 0, social: 0, paid: 0 }
      
      for_period(start_date, end_date).find_each do |session|
        source = categorize_traffic_source(session)
        result[source] += 1
      end
      
      result
    end

    def top_entry_pages(start_date: 30.days.ago, end_date: Time.current, limit: 10)
      for_period(start_date, end_date)
        .where.not(entry_page: nil)
        .group(:entry_page)
        .order('count_all DESC')
        .limit(limit)
        .count
    end

    def daily_trend(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .group("DATE(session_start)")
        .count
        .transform_keys { |k| k.to_date }
    end

    def hourly_distribution(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .group("EXTRACT(HOUR FROM session_start)")
        .count
        .transform_keys(&:to_i)
    end

    def device_breakdown(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .group(:device_type)
        .count
    end

    def geo_breakdown(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .where.not(country: nil)
        .group(:country)
        .order('count_all DESC')
        .count
    end

    def active_sessions_count
      active.count
    end

    private

    def categorize_traffic_source(session)
      return :paid if session.utm_medium&.downcase&.in?(%w[cpc ppc paid])
      return :direct if session.first_referrer_domain.blank?
      
      search_engines = %w[google bing yahoo duckduckgo]
      social_networks = %w[facebook twitter instagram linkedin pinterest tiktok]
      
      domain = session.first_referrer_domain.to_s.downcase
      
      return :organic if search_engines.any? { |se| domain.include?(se) }
      return :social if social_networks.any? { |sn| domain.include?(sn) }
      
      :referral
    end
  end

  # Instance methods
  def end_session!
    update!(
      session_end: Time.current,
      duration_seconds: calculate_duration,
      is_bounce: (page_view_count || 0) <= 1
    )
  end

  def record_page_view!
    increment!(:page_view_count)
  end

  def record_click!
    increment!(:click_count)
  end

  def mark_converted!(type, value = nil)
    update!(
      converted: true,
      conversion_type: type,
      conversion_value: value,
      conversion_time: Time.current
    )
  end

  def duration_formatted
    return 'N/A' if duration_seconds.nil? || duration_seconds.zero?
    
    minutes = duration_seconds / 60
    seconds = duration_seconds % 60
    
    if minutes > 0
      "#{minutes}m #{seconds}s"
    else
      "#{seconds}s"
    end
  end

  private

  def set_session_start
    self.session_start ||= Time.current
  end

  def calculate_duration
    return 0 unless session_start.present?
    (Time.current - session_start).to_i
  end

  # Ransack configuration
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id visitor_fingerprint session_id session_start session_end
       duration_seconds page_view_count click_count is_bounce entry_page exit_page
       first_referrer_domain utm_source utm_medium utm_campaign device_type browser os
       country region city converted conversion_type conversion_value is_returning_visitor
       created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business page_views click_events]
  end
end

