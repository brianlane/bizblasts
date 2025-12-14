# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payroll::AdpCsvBuilder do
  let(:business) { create(:business) }
  let(:config) do
    business.create_adp_payroll_export_config!(
      rounding_minutes: 15,
      round_total_hours: true,
      config: {
        'included_booking_statuses' => ['completed'],
        'default_pay_code' => 'REG',
        'timezone' => 'UTC'
      }
    )
  end

  it 'generates one CSV row per employee per day' do
    staff = create(:staff_member, business: business, adp_employee_id: 'E123', adp_pay_code: 'REG')
    create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 10), end_time: Time.utc(2025, 12, 1, 11))

    csv, summary, report = described_class.new(business: business, config: config).build(
      range_start: Date.new(2025, 12, 1),
      range_end: Date.new(2025, 12, 1)
    )

    expect(csv).to include('employee_id,work_date,pay_code,hours,department_code,job_code')
    expect(csv).to include('E123,2025-12-01,REG,1.00')

    expect(summary[:row_count]).to eq(1)
    expect(report[:errors]).to be_empty
  end

  it 'skips bookings when staff member is missing ADP employee id' do
    staff = create(:staff_member, business: business, adp_employee_id: nil)
    create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 10), end_time: Time.utc(2025, 12, 1, 11))

    csv, summary, report = described_class.new(business: business, config: config).build(
      range_start: Date.new(2025, 12, 1),
      range_end: Date.new(2025, 12, 1)
    )

    # Only header row
    expect(csv).to include('employee_id,work_date,pay_code,hours,department_code,job_code')
    expect(summary[:row_count]).to eq(0)
    expect(report[:errors].length).to eq(1)
    expect(report[:errors].first[:type]).to eq('missing_employee_id')
  end

  it 'rounds hours to nearest configured minutes' do
    staff = create(:staff_member, business: business, adp_employee_id: 'E123')
    # 1 hour 7 minutes -> 1.00 hours when rounding to 15 minutes
    create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 10), end_time: Time.utc(2025, 12, 1, 11, 7))

    csv, _summary, _report = described_class.new(business: business, config: config).build(
      range_start: Date.new(2025, 12, 1),
      range_end: Date.new(2025, 12, 1)
    )

    expect(csv).to include('E123,2025-12-01,REG,1.00')
  end

  it 'rounds after aggregation (prevents undercounting)' do
    staff = create(:staff_member, business: business, adp_employee_id: 'E123', adp_pay_code: 'REG')
    # Two separate 7-minute bookings:
    # - If you round each first: 0.00 + 0.00 = 0.00
    # - If you round after sum: 0.2333.. rounds to 0.25 (15-min increments)
    create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 10, 0), end_time: Time.utc(2025, 12, 1, 10, 7))
    create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 11, 0), end_time: Time.utc(2025, 12, 1, 11, 7))

    csv, _summary, _report = described_class.new(business: business, config: config).build(
      range_start: Date.new(2025, 12, 1),
      range_end: Date.new(2025, 12, 1)
    )

    expect(csv).to include('E123,2025-12-01,REG,0.25')
  end
end
