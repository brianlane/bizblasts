# frozen_string_literal: true

module Analytics
  # Service for calculating staff performance and productivity metrics
  class StaffPerformanceService
    include Analytics::QueryMonitoring

    attr_reader :business

    self.query_threshold = 1.0

    def initialize(business)
      @business = business
    end

    # Get staff leaderboard sorted by revenue
    def staff_leaderboard(period = 30.days, sort_by: :revenue)
      staff_members = business.staff_members.includes(:bookings)

      leaderboard_data = staff_members.map do |staff|
        {
          staff_id: staff.id,
          name: staff.full_name,
          email: staff.email,
          bookings_count: bookings_count(staff, period),
          revenue: calculate_staff_revenue(staff, period),
          utilization_rate: calculate_utilization_rate(staff, period),
          avg_rating: staff.average_rating || 0,
          avg_service_duration: calculate_avg_service_duration(staff, period),
          completion_rate: calculate_completion_rate(staff, period)
        }
      end

      # Return hash with sorted arrays for each metric
      {
        by_revenue: leaderboard_data.sort_by { |s| -s[:revenue] },
        by_bookings: leaderboard_data.sort_by { |s| -s[:bookings_count] },
        by_utilization: leaderboard_data.sort_by { |s| -s[:utilization_rate] },
        by_rating: leaderboard_data.sort_by { |s| -s[:avg_rating] }
      }
    end

    # Calculate staff utilization rate
    def calculate_utilization_rate(staff, period)
      # Available hours - assuming 8-hour workdays, 5 days/week
      days_in_period = (period / 1.day).to_i
      weeks_in_period = days_in_period / 7.0
      available_hours = weeks_in_period * 40 # 40 hours per week

      # Booked hours
      booked_minutes = staff.bookings
                           .where(created_at: period.ago..Time.current)
                           .where.not(status: ['cancelled', 'no_show'])
                           .joins(:service)
                           .sum('services.duration')

      booked_hours = booked_minutes / 60.0

      return 0 if available_hours.zero?
      ((booked_hours / available_hours) * 100).round(1)
    end

    # Get productivity trends over time
    def productivity_trends(staff, period = 90.days, interval: :week)
      bookings = staff.bookings.where(created_at: period.ago..Time.current)

      case interval
      when :day
        group_by = "DATE(bookings.created_at)"
      when :week
        group_by = "DATE_TRUNC('week', bookings.created_at)"
      when :month
        group_by = "DATE_TRUNC('month', bookings.created_at)"
      else
        group_by = "DATE_TRUNC('week', bookings.created_at)"
      end

      bookings.group(group_by)
              .select("#{group_by} as period,
                      COUNT(*) as booking_count,
                      SUM(CASE WHEN payments.status = 'completed' THEN payments.amount ELSE 0 END) as revenue")
              .joins(invoice: :payments)
              .order('period ASC')
              .map { |r|
                {
                  date: r.period,
                  bookings: r.booking_count,
                  revenue: r.revenue.to_f
                }
              }
    end

    # Compare staff performance metrics
    def compare_staff(staff_ids, period = 30.days)
      return [] if staff_ids.empty?

      staff_members = business.staff_members.where(id: staff_ids)

      staff_members.map do |staff|
        {
          staff_id: staff.id,
          name: staff.full_name,
          metrics: {
            bookings: bookings_count(staff, period),
            revenue: calculate_staff_revenue(staff, period),
            utilization: calculate_utilization_rate(staff, period),
            avg_rating: staff.average_rating || 0,
            completion_rate: calculate_completion_rate(staff, period),
            avg_service_duration: calculate_avg_service_duration(staff, period)
          }
        }
      end
    end

    # Get top performing staff for a specific metric
    def top_performers(metric, limit = 5, period = 30.days)
      leaderboard = staff_leaderboard(period, sort_by: metric)
      leaderboard.first(limit)
    end

    # Calculate capacity recommendations
    def capacity_analysis(period = 30.days)
      staff_members = business.staff_members.includes(:bookings)

      staff_analysis = staff_members.map do |staff|
        utilization = calculate_utilization_rate(staff, period)

        {
          staff_id: staff.id,
          name: staff.full_name,
          utilization_rate: utilization,
          status: determine_capacity_status(utilization),
          recommendation: capacity_recommendation(utilization)
        }
      end

      {
        staff_analysis: staff_analysis,
        summary: {
          underutilized: staff_analysis.count { |s| s[:status] == :underutilized },
          optimal: staff_analysis.count { |s| s[:status] == :optimal },
          overbooked: staff_analysis.count { |s| s[:status] == :overbooked }
        }
      }
    end

    # Get staff performance summary
    def performance_summary(period = 30.days)
      staff_members = business.staff_members.includes(:bookings)

      total_bookings = 0
      total_revenue = 0
      total_staff = staff_members.count
      active_staff_list = []
      total_utilization = 0

      staff_members.each do |staff|
        bookings = bookings_count(staff, period)
        total_bookings += bookings
        total_revenue += calculate_staff_revenue(staff, period)

        if bookings > 0
          active_staff_list << staff
          total_utilization += calculate_utilization_rate(staff, period)
        end
      end

      active_count = active_staff_list.count

      {
        total_staff: total_staff,
        active_staff: active_count,
        total_active: active_count, # Alias for view compatibility
        total_bookings: total_bookings,
        total_revenue: total_revenue,
        avg_bookings_per_staff: total_staff > 0 ? (total_bookings.to_f / total_staff).round(1) : 0,
        avg_revenue_per_staff: total_staff > 0 ? (total_revenue / total_staff).round(2) : 0,
        avg_utilization: active_count > 0 ? (total_utilization / active_count).round(1) : 0
      }
    end

    private

    def bookings_count(staff, period)
      staff.bookings
           .where(created_at: period.ago..Time.current)
           .count
    end

    def calculate_staff_revenue(staff, period)
      staff.bookings
           .where(created_at: period.ago..Time.current)
           .joins(invoice: :payments)
           .where(payments: { status: :completed })
           .sum('payments.amount').to_f
    end

    def calculate_avg_service_duration(staff, period)
      avg = staff.bookings
                .where(created_at: period.ago..Time.current)
                .joins(:service)
                .average('services.duration')

      avg ? avg.round(0) : 0
    end

    def calculate_completion_rate(staff, period)
      total_bookings = staff.bookings.where(created_at: period.ago..Time.current).count
      return 0 if total_bookings.zero?

      completed_bookings = staff.bookings
                               .where(created_at: period.ago..Time.current)
                               .where(status: :completed)
                               .count

      ((completed_bookings.to_f / total_bookings) * 100).round(1)
    end

    def determine_capacity_status(utilization_rate)
      case utilization_rate
      when 0..50 then :underutilized
      when 51..85 then :optimal
      else :overbooked
      end
    end

    def capacity_recommendation(utilization_rate)
      case determine_capacity_status(utilization_rate)
      when :underutilized
        "Consider increasing workload or marketing efforts"
      when :optimal
        "Well-balanced workload"
      when :overbooked
        "Consider hiring additional staff or limiting bookings"
      end
    end
  end
end
