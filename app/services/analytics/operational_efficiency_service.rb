# frozen_string_literal: true

module Analytics
  # Service for operational efficiency and booking analytics
  class OperationalEfficiencyService
    include Analytics::QueryMonitoring

    attr_reader :business

    self.query_threshold = 1.0

    def initialize(business)
      @business = business
    end

    # No-show analysis and patterns
    def no_show_analysis(period = 30.days)
      total_bookings = business.bookings.where(created_at: period.ago..Time.current).count
      no_shows = business.bookings.where(created_at: period.ago..Time.current, status: 'no_show')

      {
        no_show_count: no_shows.count,
        no_show_rate: total_bookings > 0 ? ((no_shows.count.to_f / total_bookings) * 100).round(2) : 0,
        patterns: analyze_no_show_patterns(no_shows),
        estimated_lost_revenue: calculate_lost_revenue(no_shows)
      }
    end

    # Cancellation analysis
    def cancellation_analysis(period = 30.days)
      total_bookings = business.bookings.where(created_at: period.ago..Time.current).count
      cancelled = business.bookings.where(created_at: period.ago..Time.current, status: :cancelled)

      {
        cancellation_count: cancelled.count,
        cancellation_rate: total_bookings > 0 ? ((cancelled.count.to_f / total_bookings) * 100).round(2) : 0,
        by_service: cancelled.group(:service_id).count,
        by_staff: cancelled.group(:staff_member_id).count,
        avg_cancellation_lead_time: calculate_avg_cancellation_lead_time(cancelled)
      }
    end

    # Peak hours analysis
    def peak_hours_heatmap(period = 90.days)
      bookings = business.bookings.where(created_at: period.ago..Time.current)

      # Create 7x24 heatmap (day of week x hour)
      heatmap = Array.new(7) { Array.new(24, 0) }

      bookings.find_each do |booking|
        next unless booking.start_time

        day = booking.start_time.wday # 0 = Sunday
        hour = booking.start_time.hour
        heatmap[day][hour] += 1
      end

      {
        heatmap: heatmap,
        busiest_day: find_busiest_day(heatmap),
        busiest_hour: find_busiest_hour(heatmap),
        slowest_day: find_slowest_day(heatmap),
        slowest_hour: find_slowest_hour(heatmap)
      }
    end

    # Average fulfillment time
    def fulfillment_metrics(period = 30.days)
      completed_bookings = business.bookings
                                  .where(created_at: period.ago..Time.current, status: :completed)

      {
        avg_duration: completed_bookings.joins(:service).average('services.duration')&.round(0) || 0,
        total_completed: completed_bookings.count,
        completion_rate: calculate_completion_rate(period),
        avg_lead_time: calculate_avg_lead_time(period)
      }
    end

    # Idle time analysis
    def idle_time_analysis(staff_member, date = Date.current)
      bookings = staff_member.bookings
                             .where('DATE(start_time) = ?', date)
                             .order(:start_time)

      return { total_idle_minutes: 0, idle_periods: [] } if bookings.count < 2

      idle_periods = []
      total_idle = 0

      bookings.each_cons(2) do |booking1, booking2|
        gap = ((booking2.start_time - booking1.end_time) / 60).to_i
        if gap > 0
          idle_periods << {
            start: booking1.end_time,
            end: booking2.start_time,
            minutes: gap
          }
          total_idle += gap
        end
      end

      {
        total_idle_minutes: total_idle,
        idle_periods: idle_periods,
        utilization_rate: calculate_day_utilization(staff_member, date)
      }
    end

    # Booking lead time analysis (time from booking created to service date)
    def lead_time_distribution(period = 30.days)
      bookings = business.bookings.where(created_at: period.ago..Time.current)

      lead_times = bookings.map do |booking|
        next unless booking.start_time && booking.created_at
        ((booking.start_time - booking.created_at) / 1.day).to_i
      end.compact

      return empty_distribution if lead_times.empty?

      {
        avg_lead_time_days: (lead_times.sum / lead_times.count.to_f).round(1),
        median_lead_time_days: lead_times.sort[lead_times.count / 2],
        same_day: lead_times.count { |d| d == 0 },
        next_day: lead_times.count { |d| d == 1 },
        within_week: lead_times.count { |d| d.between?(2, 7) },
        over_week: lead_times.count { |d| d > 7 }
      }
    end

    # Service capacity utilization
    def service_capacity_analysis(period = 30.days)
      services = business.services.includes(:bookings)

      services.map do |service|
        total_bookings = service.bookings.where(created_at: period.ago..Time.current).count
        completed = service.bookings.where(created_at: period.ago..Time.current, status: :completed).count

        {
          service_id: service.id,
          service_name: service.name,
          total_bookings: total_bookings,
          completed: completed,
          completion_rate: total_bookings > 0 ? ((completed.to_f / total_bookings) * 100).round(1) : 0,
          avg_duration: service.duration,
          revenue: service.bookings
                         .where(created_at: period.ago..Time.current)
                         .joins(invoice: :payments)
                         .where(payments: { status: :completed })
                         .sum('payments.amount').to_f
        }
      end.sort_by { |s| -s[:total_bookings] }
    end

    private

    def analyze_no_show_patterns(no_shows)
      {
        by_day_of_week: no_shows.group("EXTRACT(DOW FROM start_time)").count,
        by_hour: no_shows.group("EXTRACT(HOUR FROM start_time)").count,
        by_service: no_shows.group(:service_id).count,
        by_staff: no_shows.group(:staff_member_id).count
      }
    end

    def calculate_lost_revenue(no_shows)
      no_shows.joins(:service).sum('services.price').to_f
    end

    def calculate_avg_cancellation_lead_time(cancelled_bookings)
      lead_times = cancelled_bookings.map do |booking|
        next unless booking.start_time && booking.updated_at
        ((booking.start_time - booking.updated_at) / 1.hour).to_i
      end.compact

      lead_times.empty? ? 0 : (lead_times.sum / lead_times.count.to_f).round(1)
    end

    def find_busiest_day(heatmap)
      day_totals = heatmap.map(&:sum)
      busiest_index = day_totals.index(day_totals.max)
      Date::DAYNAMES[busiest_index]
    end

    def find_busiest_hour(heatmap)
      hour_totals = (0..23).map { |hour| heatmap.sum { |day| day[hour] } }
      hour_totals.index(hour_totals.max)
    end

    def find_slowest_day(heatmap)
      day_totals = heatmap.map(&:sum)
      slowest_index = day_totals.index(day_totals.min)
      Date::DAYNAMES[slowest_index]
    end

    def find_slowest_hour(heatmap)
      hour_totals = (0..23).map { |hour| heatmap.sum { |day| day[hour] } }
      hour_totals.index(hour_totals.min)
    end

    def calculate_completion_rate(period)
      total = business.bookings.where(created_at: period.ago..Time.current).count
      completed = business.bookings.where(created_at: period.ago..Time.current, status: :completed).count

      total > 0 ? ((completed.to_f / total) * 100).round(1) : 0
    end

    def calculate_avg_lead_time(period)
      bookings = business.bookings.where(created_at: period.ago..Time.current)

      lead_times = bookings.map do |booking|
        next unless booking.start_time && booking.created_at
        ((booking.start_time - booking.created_at) / 1.day).to_i
      end.compact

      lead_times.empty? ? 0 : (lead_times.sum / lead_times.count.to_f).round(1)
    end

    def calculate_day_utilization(staff_member, date)
      total_minutes = 8 * 60 # 8-hour workday
      booked_minutes = staff_member.bookings
                                   .where('DATE(start_time) = ?', date)
                                   .joins(:service)
                                   .sum('services.duration')

      ((booked_minutes.to_f / total_minutes) * 100).round(1)
    end

    def empty_distribution
      {
        avg_lead_time_days: 0,
        median_lead_time_days: 0,
        same_day: 0,
        next_day: 0,
        within_week: 0,
        over_week: 0
      }
    end
  end
end
