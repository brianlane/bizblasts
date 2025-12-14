# frozen_string_literal: true

require 'csv'

module Payroll
  class AdpCsvBuilder
    # Minimal, broadly-compatible time import CSV.
    # Columns:
    # - employee_id
    # - work_date (YYYY-MM-DD)
    # - pay_code
    # - hours
    # - department_code (optional)
    # - job_code (optional)
    def initialize(business:, config:)
      @business = business
      @config = config
    end

    def build(range_start:, range_end:)
      tz = @config.timezone
      statuses = @config.included_booking_statuses

      bookings = @business.bookings
                          .where(status: statuses)
                          .where(start_time: range_start.beginning_of_day..range_end.end_of_day)
                          .includes(:staff_member)

      errors = []
      rows_by_key = Hash.new { |h, k| h[k] = { hours: 0.0, sample_booking_ids: [] } }

      bookings.find_each do |booking|
        staff = booking.staff_member
        next unless staff

        employee_id = staff.adp_employee_id.to_s.strip
        if employee_id.blank?
          errors << {
            type: 'missing_employee_id',
            staff_member_id: staff.id,
            staff_member_name: staff.name,
            booking_id: booking.id
          }
          next
        end

        # Compute work date in configured timezone
        work_date = booking.start_time&.in_time_zone(tz)&.to_date
        next unless work_date

        # Compute raw hours
        raw_seconds = if booking.start_time && booking.end_time
          booking.end_time - booking.start_time
        else
          0
        end

        raw_hours = (raw_seconds / 3600.0)
        next if raw_hours <= 0

        rounded_hours = if @config.round_total_hours
          round_hours(raw_hours, @config.round_to_minutes)
        else
          raw_hours
        end

        pay_code = staff.adp_pay_code.to_s.strip.presence || @config.default_pay_code
        dept = staff.adp_department_code.to_s.strip.presence
        job = staff.adp_job_code.to_s.strip.presence

        key = [employee_id, work_date.iso8601, pay_code, dept, job]
        rows_by_key[key][:hours] += rounded_hours
        rows_by_key[key][:sample_booking_ids] << booking.id
      end

      csv_string = CSV.generate(headers: true) do |csv|
        csv << %w[employee_id work_date pay_code hours department_code job_code]

        rows_by_key.sort_by { |(emp, date, code, dept, job), _| [emp, date, code, dept.to_s, job.to_s] }.each do |key, agg|
          emp, date, code, dept, job = key
          csv << [emp, date, code, format('%.2f', agg[:hours]), dept, job]
        end
      end

      summary = {
        range_start: range_start.iso8601,
        range_end: range_end.iso8601,
        booking_count: bookings.size,
        row_count: rows_by_key.size,
        skipped_missing_employee_id: errors.count { |e| e[:type] == 'missing_employee_id' }
      }

      [csv_string, summary, { errors: errors }]
    end

    private

    # Round hours to nearest N minutes.
    def round_hours(hours, minutes)
      minutes = minutes.to_i
      return hours if minutes <= 0

      step = minutes / 60.0
      (hours / step).round * step
    end
  end
end
