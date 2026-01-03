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
    # OPTIMIZED: Uses SQL aggregation instead of N+1 queries
    def staff_leaderboard(period = 30.days, sort_by: :revenue)
      # Calculate metrics using SQL JOIN and aggregation
      leaderboard_data = business.staff_members
        .left_joins(bookings: { invoice: :payments })
        .where('bookings.created_at >= ? OR bookings.id IS NULL', period.ago)
        .group('staff_members.id')
        .select(
          'staff_members.id as staff_id',
          "CONCAT(staff_members.first_name, ' ', staff_members.last_name) as name",
          'staff_members.email',
          'staff_members.average_rating as avg_rating',
          'COUNT(DISTINCT bookings.id) as bookings_count',
          'COALESCE(SUM(CASE WHEN payments.status = 1 THEN payments.amount ELSE 0 END), 0) as revenue',
          calculate_utilization_rate_sql(period),
          'COALESCE(AVG(services.duration), 0) as avg_service_duration',
          calculate_completion_rate_sql(period)
        )
        .joins('LEFT JOIN services ON services.id = bookings.service_id')

      # Convert to array of hashes
      data = leaderboard_data.map do |staff|
        {
          staff_id: staff.staff_id,
          name: staff.name,
          email: staff.email,
          bookings_count: staff.bookings_count || 0,
          revenue: (staff.revenue || 0).to_f.round(2),
          utilization_rate: (staff.utilization_rate || 0).to_f.round(1),
          avg_rating: (staff.avg_rating || 0).to_f,
          avg_service_duration: (staff.avg_service_duration || 0).to_f.round(0),
          completion_rate: (staff.completion_rate || 0).to_f.round(1)
        }
      end

      # Return hash with sorted arrays for each metric
      {
        by_revenue: data.sort_by { |s| -s[:revenue] },
        by_bookings: data.sort_by { |s| -s[:bookings_count] },
        by_utilization: data.sort_by { |s| -s[:utilization_rate] },
        by_rating: data.sort_by { |s| -s[:avg_rating] }
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
    # OPTIMIZED: Uses SQL aggregation instead of N+1 queries
    def performance_summary(period = 30.days)
      total_staff = business.staff_members.count

      # Use SQL to calculate all metrics in one query
      summary = business.staff_members
        .left_joins(bookings: { invoice: :payments })
        .where('bookings.created_at >= ? OR bookings.id IS NULL', period.ago)
        .select(
          'COUNT(DISTINCT staff_members.id) as total_staff',
          'COUNT(DISTINCT CASE WHEN bookings.id IS NOT NULL THEN staff_members.id END) as active_staff',
          'COUNT(DISTINCT bookings.id) as total_bookings',
          'COALESCE(SUM(CASE WHEN payments.status = 1 THEN payments.amount ELSE 0 END), 0) as total_revenue'
        )
        .first

      active_count = summary.active_staff || 0

      {
        total_staff: total_staff,
        active_staff: active_count,
        total_active: active_count, # Alias for view compatibility
        total_bookings: summary.total_bookings || 0,
        total_revenue: (summary.total_revenue || 0).to_f.round(2),
        avg_bookings_per_staff: total_staff > 0 ? ((summary.total_bookings || 0).to_f / total_staff).round(1) : 0,
        avg_revenue_per_staff: total_staff > 0 ? ((summary.total_revenue || 0).to_f / total_staff).round(2) : 0,
        avg_utilization: active_count > 0 ? calculate_avg_utilization_sql(period) : 0
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

    # SQL helper methods for performance calculations
    def calculate_utilization_rate_sql(period)
      days_in_period = (period / 1.day).to_i
      weeks_in_period = days_in_period / 7.0
      available_hours = weeks_in_period * 40 # 40 hours per week

      <<~SQL.squish
        ROUND(
          (COALESCE(SUM(services.duration), 0) / 60.0) / NULLIF(#{available_hours}, 0) * 100,
          1
        ) as utilization_rate
      SQL
    end

    def calculate_completion_rate_sql(period)
      <<~SQL.squish
        ROUND(
          COALESCE(
            COUNT(CASE WHEN bookings.status = 3 THEN 1 END)::FLOAT /
            NULLIF(COUNT(bookings.id), 0) * 100,
            0
          ),
          1
        ) as completion_rate
      SQL
    end

    def calculate_avg_utilization_sql(period)
      days_in_period = (period / 1.day).to_i
      weeks_in_period = days_in_period / 7.0
      available_hours = weeks_in_period * 40

      result = business.staff_members
        .left_joins(bookings: :service)
        .where('bookings.created_at >= ? OR bookings.id IS NULL', period.ago)
        .where('bookings.status NOT IN (?) OR bookings.id IS NULL', ['cancelled', 'no_show'])
        .group('staff_members.id')
        .select("(COALESCE(SUM(services.duration), 0) / 60.0) / NULLIF(#{available_hours}, 0) * 100 as util_rate")
        .having('COUNT(bookings.id) > 0')

      rates = result.pluck(:util_rate).compact
      rates.empty? ? 0 : (rates.sum / rates.count).round(1)
    end
  end
end
