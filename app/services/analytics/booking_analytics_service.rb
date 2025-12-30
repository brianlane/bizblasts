# frozen_string_literal: true

module Analytics
  # Service for analyzing booking performance and metrics
  class BookingAnalyticsService
    attr_reader :business

    def initialize(business)
      @business = business
    end

    # Get comprehensive booking metrics for a period
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Booking metrics
    def metrics(start_date: 30.days.ago, end_date: Time.current)
      bookings = business.bookings.where(created_at: start_date..end_date)
      
      {
        total: bookings.count,
        completed: bookings.completed.count,
        cancelled: bookings.cancelled.count,
        no_show: bookings.no_show.count,
        pending: bookings.pending.count,
        confirmed: bookings.confirmed.count,
        completion_rate: calculate_completion_rate(bookings),
        cancellation_rate: calculate_cancellation_rate(bookings),
        no_show_rate: calculate_no_show_rate(bookings),
        total_revenue: calculate_total_revenue(bookings),
        average_value: calculate_average_value(bookings),
        bookings_by_source: bookings_by_source(start_date: start_date, end_date: end_date),
        lead_time: calculate_average_lead_time(bookings),
        peak_hours: calculate_peak_hours(bookings),
        peak_days: calculate_peak_days(bookings)
      }
    end

    # Get booking trend data
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @param granularity [Symbol] :daily, :weekly, :monthly
    # @return [Array<Hash>] Trend data points
    def trend(start_date: 30.days.ago, end_date: Time.current, granularity: :daily)
      bookings = business.bookings.where(created_at: start_date..end_date)
      
      case granularity
      when :daily
        bookings.group("DATE(created_at)").count.map do |date, count|
          { date: date, bookings: count }
        end
      when :weekly
        bookings.group("DATE_TRUNC('week', created_at)").count.map do |date, count|
          { date: date.to_date, bookings: count }
        end
      when :monthly
        bookings.group("DATE_TRUNC('month', created_at)").count.map do |date, count|
          { date: date.to_date, bookings: count }
        end
      end
    end

    # Get top performing services by bookings
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @param limit [Integer] Number of services to return
    # @return [Array<Hash>] Top services with metrics
    def top_services(start_date: 30.days.ago, end_date: Time.current, limit: 10)
      completed_status = Booking.statuses[:completed]

      bookings = business.bookings
        .where(created_at: start_date..end_date)
        .joins(:service)
        .group('services.id', 'services.name', 'services.price')
        .select(
          'services.id',
          'services.name',
          'services.price',
          'COUNT(*) as booking_count',
          "SUM(CASE WHEN bookings.status = #{completed_status} THEN 1 ELSE 0 END) as completed_count"
        )
        .order('booking_count DESC')
        .limit(limit)
      
      bookings.map do |booking|
        {
          service_id: booking.id,
          service_name: booking.name,
          price: booking.price.to_f,
          bookings: booking.booking_count,
          completed: booking.completed_count,
          revenue: (booking.price.to_f * booking.completed_count).round(2),
          completion_rate: booking.booking_count > 0 ? 
            (booking.completed_count.to_f / booking.booking_count * 100).round(2) : 0
        }
      end
    end

    # Get staff performance metrics
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Array<Hash>] Staff performance data
    def staff_performance(start_date: 30.days.ago, end_date: Time.current)
      staff_members = business.staff_members.active
      
      staff_members.map do |staff|
        bookings = business.bookings
          .where(staff_member: staff, created_at: start_date..end_date)
        
        {
          staff_id: staff.id,
          staff_name: staff.name,
          total_bookings: bookings.count,
          completed_bookings: bookings.completed.count,
          cancelled_bookings: bookings.cancelled.count,
          no_show_bookings: bookings.no_show.count,
          completion_rate: bookings.count > 0 ?
            (bookings.completed.count.to_f / bookings.count * 100).round(2) : 0,
          utilization_rate: calculate_staff_utilization(staff, start_date, end_date),
          avg_booking_value: calculate_staff_avg_value(bookings)
        }
      end.sort_by { |s| -s[:total_bookings] }
    end

    # Get booking source attribution
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Bookings by source
    def bookings_by_source(start_date: 30.days.ago, end_date: Time.current)
      # Get sessions that converted to bookings
      converted_sessions = business.visitor_sessions
        .where(converted: true, conversion_type: 'booking')
        .where(conversion_time: start_date..end_date)
      
      sources = { direct: 0, organic: 0, social: 0, referral: 0, paid: 0, other: 0 }
      
      converted_sessions.find_each do |session|
        channel = determine_channel(session)
        sources[channel.to_sym] = (sources[channel.to_sym] || 0) + 1
      end
      
      # Add bookings without session attribution
      attributed_count = sources.values.sum
      total_bookings = business.bookings.where(created_at: start_date..end_date).count
      sources[:other] += (total_bookings - attributed_count)
      
      sources
    end

    # Get booking heatmap data (day of week x hour)
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Hash] Heatmap data
    def booking_heatmap(start_date: 30.days.ago, end_date: Time.current)
      bookings = business.bookings.where(start_time: start_date..end_date)
      
      heatmap = {}
      (0..6).each { |day| heatmap[day] = {} }
      
      bookings.find_each do |booking|
        day = booking.start_time.wday
        hour = booking.start_time.hour
        heatmap[day][hour] ||= 0
        heatmap[day][hour] += 1
      end
      
      heatmap
    end

    # Calculate booking conversion rate from page views
    # @param start_date [Date] Start of period
    # @param end_date [Date] End of period
    # @return [Float] Conversion rate percentage
    def booking_conversion_rate(start_date: 30.days.ago, end_date: Time.current)
      # Count unique visitors who viewed booking-related pages
      booking_page_visitors = business.page_views
        .for_period(start_date, end_date)
        .where("page_path LIKE '%booking%' OR page_path LIKE '%calendar%' OR page_type = 'booking'")
        .distinct
        .count(:visitor_fingerprint)
      
      # Count completed bookings
      completed_bookings = business.bookings
        .where(created_at: start_date..end_date)
        .completed
        .count
      
      return 0.0 if booking_page_visitors.zero?
      
      (completed_bookings.to_f / booking_page_visitors * 100).round(2)
    end

    private

    def calculate_completion_rate(bookings)
      total = bookings.count
      return 0.0 if total.zero?
      
      (bookings.completed.count.to_f / total * 100).round(2)
    end

    def calculate_cancellation_rate(bookings)
      total = bookings.count
      return 0.0 if total.zero?
      
      (bookings.cancelled.count.to_f / total * 100).round(2)
    end

    def calculate_no_show_rate(bookings)
      total = bookings.count
      return 0.0 if total.zero?
      
      (bookings.no_show.count.to_f / total * 100).round(2)
    end

    def calculate_total_revenue(bookings)
      bookings.completed.joins(:service).sum('services.price').to_f
    end

    def calculate_average_value(bookings)
      completed = bookings.completed.joins(:service)
      return 0.0 if completed.count.zero?
      
      (completed.sum('services.price').to_f / completed.count).round(2)
    end

    def calculate_average_lead_time(bookings)
      lead_times = bookings.map do |booking|
        next nil unless booking.start_time && booking.created_at
        (booking.start_time.to_date - booking.created_at.to_date).to_i
      end.compact
      
      return 0 if lead_times.empty?
      
      (lead_times.sum.to_f / lead_times.size).round(1)
    end

    def calculate_peak_hours(bookings)
      bookings
        .group("EXTRACT(HOUR FROM start_time)")
        .count
        .sort_by { |_, count| -count }
        .first(5)
        .to_h
        .transform_keys(&:to_i)
    end

    def calculate_peak_days(bookings)
      day_names = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
      
      bookings
        .group("EXTRACT(DOW FROM start_time)")
        .count
        .sort_by { |_, count| -count }
        .map { |day, count| { day: day_names[day.to_i], count: count } }
    end

    def calculate_staff_utilization(staff, start_date, end_date)
      # Calculate utilization based on booked hours vs available hours
      bookings = business.bookings.where(staff_member: staff, start_time: start_date..end_date)
      
      total_booked_minutes = bookings.sum do |booking|
        booking.service&.duration || 60
      end
      
      # Assume 8 hours per working day, 5 days per week
      working_days = ((end_date.to_date - start_date.to_date).to_i * 5 / 7.0).ceil
      available_minutes = working_days * 8 * 60
      
      return 0.0 if available_minutes.zero?
      
      (total_booked_minutes.to_f / available_minutes * 100).round(2)
    end

    def calculate_staff_avg_value(bookings)
      completed = bookings.completed.joins(:service)
      return 0.0 if completed.count.zero?
      
      (completed.sum('services.price').to_f / completed.count).round(2)
    end

    def determine_channel(session)
      if session.utm_medium.present?
        return 'paid' if session.utm_medium.downcase.in?(%w[cpc ppc paid])
        return 'social' if session.utm_medium.downcase == 'social'
      end
      
      return 'direct' if session.first_referrer_domain.blank?
      
      domain = session.first_referrer_domain.to_s.downcase
      
      return 'organic' if %w[google bing yahoo].any? { |se| domain.include?(se) }
      return 'social' if %w[facebook twitter instagram linkedin].any? { |sn| domain.include?(sn) }
      
      'referral'
    end
  end
end

