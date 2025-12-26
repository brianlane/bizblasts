# frozen_string_literal: true

class ClickEvent < ApplicationRecord
  include TenantScoped

  belongs_to :business
  belongs_to :target, polymorphic: true, optional: true
  belongs_to :visitor_session, primary_key: :session_id, foreign_key: :session_id, optional: true

  # Validations
  validates :visitor_fingerprint, presence: true
  validates :session_id, presence: true
  validates :element_type, presence: true
  validates :page_path, presence: true

  # Enums
  enum :element_type, {
    button: 'button',
    link: 'link',
    cta: 'cta',
    form_submit: 'form_submit',
    image: 'image',
    card: 'card'
  }, prefix: true

  enum :category, {
    booking: 'booking',
    product: 'product',
    service: 'service',
    contact: 'contact',
    navigation: 'navigation',
    social: 'social',
    estimate: 'estimate',
    phone: 'phone',
    email: 'email',
    external: 'external',
    other: 'other'
  }, prefix: true

  enum :action, {
    view: 'view',
    click: 'click',
    add_to_cart: 'add_to_cart',
    book: 'book',
    submit: 'submit',
    call: 'call',
    email_click: 'email_click',
    share: 'share',
    download: 'download'
  }, prefix: true

  # Scopes
  scope :for_period, ->(start_date, end_date) { where(created_at: start_date.beginning_of_day..end_date.end_of_day) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :last_7_days, -> { where(created_at: 7.days.ago.beginning_of_day..Time.current.end_of_day) }
  scope :last_30_days, -> { where(created_at: 30.days.ago.beginning_of_day..Time.current.end_of_day) }
  
  scope :conversions, -> { where(is_conversion: true) }
  scope :booking_clicks, -> { where(category: :booking) }
  scope :product_clicks, -> { where(category: :product) }
  scope :service_clicks, -> { where(category: :service) }
  scope :contact_clicks, -> { where(category: :contact) }

  # Class methods for analytics
  class << self
    def total_clicks(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date).count
    end

    def conversion_count(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date).conversions.count
    end

    def conversion_rate(start_date: 30.days.ago, end_date: Time.current)
      total = total_clicks(start_date: start_date, end_date: end_date)
      return 0.0 if total.zero?
      (conversion_count(start_date: start_date, end_date: end_date).to_f / total * 100).round(2)
    end

    def total_conversion_value(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date).conversions.sum(:conversion_value)
    end

    def clicks_by_category(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .group(:category)
        .count
    end

    def clicks_by_element_type(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .group(:element_type)
        .count
    end

    def top_clicked_elements(start_date: 30.days.ago, end_date: Time.current, limit: 10)
      for_period(start_date, end_date)
        .group(:element_identifier, :element_text)
        .order('count_all DESC')
        .limit(limit)
        .count
    end

    def conversion_funnel(start_date: 30.days.ago, end_date: Time.current)
      events = for_period(start_date, end_date)
      
      {
        page_views: events.count,
        service_clicks: events.service_clicks.count,
        booking_started: events.where(conversion_type: 'booking_started').count,
        booking_completed: events.where(conversion_type: 'booking_completed').count
      }
    end

    def daily_trend(start_date: 30.days.ago, end_date: Time.current)
      for_period(start_date, end_date)
        .group("DATE(created_at)")
        .count
        .transform_keys { |k| k.to_date }
    end
  end

  # Instance methods
  def mark_as_conversion!(conversion_type, value = nil)
    update!(
      is_conversion: true,
      conversion_type: conversion_type,
      conversion_value: value
    )
  end

  # Ransack configuration
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id visitor_fingerprint session_id element_type element_identifier
       element_text page_path category action target_type target_id conversion_value
       is_conversion conversion_type created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business target visitor_session]
  end
end

