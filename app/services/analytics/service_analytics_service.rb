# frozen_string_literal: true

module Analytics
  # Service for analyzing service page performance and booking conversion
  class ServiceAnalyticsService
    attr_reader :business

    def initialize(business)
      @business = business
    end

    # Get comprehensive service metrics for a period
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Service metrics
    def metrics(start_date: 30.days.ago, end_date: Time.current)
      services = business.services.active
      
      {
        total_services: services.count,
        total_service_views: service_page_views(start_date, end_date),
        total_service_clicks: service_clicks(start_date, end_date),
        total_bookings: service_bookings(start_date, end_date),
        view_to_booking_rate: calculate_view_to_booking_rate(start_date, end_date),
        top_viewed_services: top_viewed_services(start_date: start_date, end_date: end_date),
        top_booked_services: top_booked_services(start_date: start_date, end_date: end_date),
        view_booking_gap: calculate_view_booking_gap(start_date, end_date),
        revenue_by_service: revenue_by_service(start_date, end_date),
        service_category_breakdown: service_category_breakdown
      }
    end

    # Get services ranked by page views
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @param limit [Integer] Number of services to return
    # @return [Array<Hash>] Top viewed services
    def top_viewed_services(start_date: 30.days.ago, end_date: Time.current, limit: 10)
      clicks = business.click_events
        .for_period(start_date, end_date)
        .where(target_type: 'Service')
        .where.not(target_id: nil)
        .group(:target_id)
        .order('count_all DESC')
        .limit(limit)
        .count
      
      clicks.map do |service_id, views|
        service = Service.find_by(id: service_id)
        next nil unless service
        
        bookings = service.bookings.where(created_at: start_date..end_date).count
        
        {
          service_id: service.id,
          service_name: service.name,
          price: service.price.to_f,
          duration: service.duration,
          views: views,
          bookings: bookings,
          conversion_rate: views > 0 ? (bookings.to_f / views * 100).round(2) : 0
        }
      end.compact
    end

    # Get services ranked by bookings
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @param limit [Integer] Number of services to return
    # @return [Array<Hash>] Top booked services
    def top_booked_services(start_date: 30.days.ago, end_date: Time.current, limit: 10)
      completed_status = Booking.statuses[:completed]

      business.services
        .joins(:bookings)
        .where(bookings: { created_at: start_date..end_date })
        .group('services.id', 'services.name', 'services.price', 'services.duration')
        .select(
          'services.id',
          'services.name',
          'services.price',
          'services.duration',
          'COUNT(bookings.id) as booking_count',
          "SUM(CASE WHEN bookings.status = #{completed_status} THEN 1 ELSE 0 END) as completed_count"
        )
        .order('booking_count DESC')
        .limit(limit)
        .map do |service|
          views = service_views_for(service.id, start_date, end_date)
          
          {
            service_id: service.id,
            service_name: service.name,
            price: service.price.to_f,
            duration: service.duration,
            bookings: service.booking_count,
            completed: service.completed_count,
            views: views,
            conversion_rate: views > 0 ? (service.booking_count.to_f / views * 100).round(2) : 0,
            revenue: (service.price.to_f * service.completed_count).round(2)
          }
        end
    end

    # Identify gap between most viewed and most booked (opportunity analysis)
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Array<Hash>] Services with high views but low conversions
    def calculate_view_booking_gap(start_date, end_date)
      services = business.services.active
      
      service_data = services.map do |service|
        views = service_views_for(service.id, start_date, end_date)
        bookings = service.bookings.where(created_at: start_date..end_date).count
        
        conversion_rate = views > 0 ? (bookings.to_f / views * 100).round(2) : 0
        
        {
          service_id: service.id,
          service_name: service.name,
          views: views,
          bookings: bookings,
          conversion_rate: conversion_rate,
          gap_score: views > 10 ? (views - bookings * 10).to_f / views : 0
        }
      end
      
      # Return services with high views but low conversion (high gap score)
      service_data
        .select { |s| s[:views] >= 10 && s[:conversion_rate] < 10 }
        .sort_by { |s| -s[:gap_score] }
        .first(5)
    end

    # Get revenue breakdown by service
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Revenue by service
    def revenue_by_service(start_date, end_date)
      business.services
        .joins(:bookings)
        .where(bookings: { created_at: start_date..end_date, status: :completed })
        .group('services.id', 'services.name')
        .select('services.id', 'services.name', 'COUNT(*) * services.price as revenue')
        .order('revenue DESC')
        .each_with_object({}) do |service, hash|
          hash[service.name] = service.revenue.to_f
        end
    end

    # Get service engagement funnel
    # @param service_id [Integer] Service ID to analyze
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Funnel metrics
    def service_funnel(service_id, start_date: 30.days.ago, end_date: Time.current)
      service = business.services.find_by(id: service_id)
      return nil unless service
      
      clicks = business.click_events
        .for_period(start_date, end_date)
        .where(target_type: 'Service', target_id: service_id)
      
      bookings = service.bookings.where(created_at: start_date..end_date)
      
      {
        service_name: service.name,
        page_views: clicks.count,
        unique_viewers: clicks.distinct.count(:visitor_fingerprint),
        booking_button_clicks: clicks.where(category: 'booking').count,
        bookings_created: bookings.count,
        bookings_completed: bookings.completed.count,
        view_to_click_rate: clicks.count > 0 ?
          (clicks.where(category: 'booking').count.to_f / clicks.count * 100).round(2) : 0,
        click_to_book_rate: clicks.where(category: 'booking').count > 0 ?
          (bookings.count.to_f / clicks.where(category: 'booking').count * 100).round(2) : 0
      }
    end

    # Compare service performance
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Array<Hash>] All services with comparative metrics
    def service_comparison(start_date: 30.days.ago, end_date: Time.current)
      business.services.active.map do |service|
        views = service_views_for(service.id, start_date, end_date)
        bookings = service.bookings.where(created_at: start_date..end_date)
        completed = bookings.completed.count
        
        {
          service_id: service.id,
          service_name: service.name,
          price: service.price.to_f,
          duration: service.duration,
          views: views,
          bookings: bookings.count,
          completed: completed,
          revenue: (service.price.to_f * completed).round(2),
          conversion_rate: views > 0 ? (bookings.count.to_f / views * 100).round(2) : 0,
          completion_rate: bookings.count > 0 ? 
            (completed.to_f / bookings.count * 100).round(2) : 0
        }
      end.sort_by { |s| -s[:revenue] }
    end

    private

    def service_page_views(start_date, end_date)
      business.page_views
        .for_period(start_date, end_date)
        .where("page_path LIKE '%/services%' OR page_type = 'services'")
        .count
    end

    def service_clicks(start_date, end_date)
      business.click_events
        .for_period(start_date, end_date)
        .service_clicks
        .count
    end

    def service_bookings(start_date, end_date)
      business.bookings
        .where(created_at: start_date..end_date)
        .count
    end

    def service_views_for(service_id, start_date, end_date)
      business.click_events
        .for_period(start_date, end_date)
        .where(target_type: 'Service', target_id: service_id)
        .count
    end

    def calculate_view_to_booking_rate(start_date, end_date)
      views = service_clicks(start_date, end_date)
      bookings = service_bookings(start_date, end_date)
      
      return 0.0 if views.zero?
      (bookings.to_f / views * 100).round(2)
    end

    def service_category_breakdown
      # Group services by category/type if you have categories
      # For now, return by active status
      {
        active: business.services.active.count,
        inactive: business.services.where(active: false).count,
        total: business.services.count
      }
    end
  end
end

