# frozen_string_literal: true

module Payroll
  class AdpPreviewBuilder
    def initialize(business:, config:)
      @business = business
      @config = config
    end

    # Returns [rows, summary, error_report]
    # rows: array of hashes suitable for UI display
    def build(range_start:, range_end:)
      tz = @config.timezone
      statuses = @config.included_booking_statuses

      bookings = @business.bookings
                          .where(status: statuses)
                          .where(start_time: range_start.beginning_of_day..range_end.end_of_day)
                          .includes(:staff_member)

      errors = []
      rows_by_key = Hash.new { |h, k| h[k] = { hours: 0.0, booking_ids: [], staff_member_ids: [], staff_member_names: [] } }

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

        work_date = booking.start_time&.in_time_zone(tz)&.to_date
        next unless work_date

        raw_seconds = if booking.start_time && booking.end_time
          booking.end_time - booking.start_time
        else
          0
        end

        raw_hours = (raw_seconds / 3600.0)
        next if raw_hours <= 0

        hours = if @config.round_total_hours
          round_hours(raw_hours, @config.round_to_minutes)
        else
          raw_hours
        end

        pay_code = staff.adp_pay_code.to_s.strip.presence || @config.default_pay_code
        dept = staff.adp_department_code.to_s.strip.presence
        job = staff.adp_job_code.to_s.strip.presence

        key = [employee_id, work_date.iso8601, pay_code, dept, job]
        rows_by_key[key][:hours] += hours
        rows_by_key[key][:booking_ids] << booking.id
        rows_by_key[key][:staff_member_ids] << staff.id
        rows_by_key[key][:staff_member_names] << staff.name
      end

      rows = rows_by_key.sort_by { |(emp, date, code, dept, job), _| [emp, date, code, dept.to_s, job.to_s] }.map do |key, agg|
        emp, date, code, dept, job = key
        {
          employee_id: emp,
          work_date: date,
          pay_code: code,
          hours: agg[:hours].round(2),
          department_code: dept,
          job_code: job,
          staff_member_ids: agg[:staff_member_ids].uniq,
          staff_member_names: agg[:staff_member_names].uniq,
          booking_ids: agg[:booking_ids].uniq
        }
      end

      summary = {
        range_start: range_start.iso8601,
        range_end: range_end.iso8601,
        booking_count: bookings.size,
        row_count: rows.size,
        skipped_missing_employee_id: errors.count { |e| e[:type] == 'missing_employee_id' }
      }

      [rows, summary, { errors: errors }]
    end

    private

    def round_hours(hours, minutes)
      minutes = minutes.to_i
      return hours if minutes <= 0

      step = minutes / 60.0
      (hours / step).round * step
    end
  end
end
