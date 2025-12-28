# frozen_string_literal: true

class AnalyticsSnapshot < ApplicationRecord
  include TenantScoped

  belongs_to :business

  # Validations
  validates :snapshot_type, presence: true, inclusion: { in: %w[daily weekly monthly] }
  validates :period_start, presence: true
  validates :period_end, presence: true
  validates :generated_at, presence: true
  validate :period_end_after_start

  # Scopes
  scope :daily, -> { where(snapshot_type: 'daily') }
  scope :weekly, -> { where(snapshot_type: 'weekly') }
  scope :monthly, -> { where(snapshot_type: 'monthly') }
  scope :for_period, ->(start_date, end_date) { where('period_start >= ? AND period_end <= ?', start_date, end_date) }
  scope :recent, -> { order(period_start: :desc) }

  # Class methods
  class << self
    def latest_daily
      daily.recent.first
    end

    def latest_weekly
      weekly.recent.first
    end

    def latest_monthly
      monthly.recent.first
    end

    def for_date(date)
      daily.find_by(period_start: date, period_end: date)
    end

    def for_week(date)
      week_start = date.beginning_of_week
      week_end = date.end_of_week
      weekly.find_by(period_start: week_start, period_end: week_end)
    end

    def for_month(date)
      month_start = date.beginning_of_month
      month_end = date.end_of_month
      monthly.find_by(period_start: month_start, period_end: month_end)
    end

    def trend_data(type: 'daily', limit: 30)
      where(snapshot_type: type)
        .recent
        .limit(limit)
        .pluck(:period_start, :unique_visitors, :total_page_views, :total_sessions)
        .reverse
        .map do |period_start, visitors, page_views, sessions|
          {
            date: period_start,
            visitors: visitors,
            page_views: page_views,
            sessions: sessions
          }
        end
    end

    def aggregate_metrics(type: 'daily', start_date: 30.days.ago.to_date, end_date: Date.current)
      snapshots = where(snapshot_type: type).for_period(start_date, end_date)
      
      return empty_aggregate if snapshots.empty?

      {
        unique_visitors: snapshots.sum(:unique_visitors),
        total_page_views: snapshots.sum(:total_page_views),
        total_sessions: snapshots.sum(:total_sessions),
        avg_bounce_rate: snapshots.average(:bounce_rate)&.round(2) || 0,
        avg_session_duration: snapshots.average(:avg_session_duration)&.round(0) || 0,
        avg_pages_per_session: snapshots.average(:pages_per_session)&.round(2) || 0,
        total_conversions: snapshots.sum(:total_conversions),
        avg_conversion_rate: snapshots.average(:conversion_rate)&.round(2) || 0,
        total_conversion_value: snapshots.sum(:total_conversion_value)
      }
    end

    def empty_aggregate
      {
        unique_visitors: 0,
        total_page_views: 0,
        total_sessions: 0,
        avg_bounce_rate: 0.0,
        avg_session_duration: 0,
        avg_pages_per_session: 0.0,
        total_conversions: 0,
        avg_conversion_rate: 0.0,
        total_conversion_value: 0.0
      }
    end
  end

  # Instance methods
  def booking_stats
    (booking_metrics.presence || {}).with_indifferent_access
  end

  def product_stats
    (product_metrics.presence || {}).with_indifferent_access
  end

  def service_stats
    (service_metrics.presence || {}).with_indifferent_access
  end

  def estimate_stats
    (estimate_metrics.presence || {}).with_indifferent_access
  end

  def traffic_source_stats
    (traffic_sources.presence || {}).with_indifferent_access
  end

  def top_referrer_list
    top_referrers.presence || []
  end

  def top_page_list
    top_pages.presence || []
  end

  def device_stats
    (device_breakdown.presence || {}).with_indifferent_access
  end

  def geo_stats
    (geo_breakdown.presence || {}).with_indifferent_access
  end

  def campaign_stats
    (campaign_metrics.presence || {}).with_indifferent_access
  end

  def period_label
    case snapshot_type
    when 'daily'
      period_start.strftime('%b %d, %Y')
    when 'weekly'
      "#{period_start.strftime('%b %d')} - #{period_end.strftime('%b %d, %Y')}"
    when 'monthly'
      period_start.strftime('%B %Y')
    end
  end

  def avg_session_duration_formatted
    return 'N/A' if avg_session_duration.nil? || avg_session_duration.zero?
    
    minutes = avg_session_duration / 60
    seconds = avg_session_duration % 60
    
    if minutes > 0
      "#{minutes}m #{seconds}s"
    else
      "#{seconds}s"
    end
  end

  private

  def period_end_after_start
    return unless period_start && period_end
    
    if period_end < period_start
      errors.add(:period_end, 'must be after or equal to period start')
    end
  end

  # Ransack configuration
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id snapshot_type period_start period_end unique_visitors
       total_page_views total_sessions bounce_rate avg_session_duration
       pages_per_session total_conversions conversion_rate total_conversion_value
       generated_at created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business]
  end
end

