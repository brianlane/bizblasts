# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payroll::AdpPreviewBuilder do
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

  it 'returns preview rows and totals-ready hours' do
    staff = create(:staff_member, business: business, adp_employee_id: 'E123', adp_pay_code: 'REG')
    create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 10), end_time: Time.utc(2025, 12, 1, 11, 7))

    rows, summary, report = described_class.new(business: business, config: config).build(
      range_start: Date.new(2025, 12, 1),
      range_end: Date.new(2025, 12, 1)
    )

    expect(summary[:row_count]).to eq(1)
    expect(report[:errors]).to be_empty

    row = rows.first
    expect(row[:employee_id]).to eq('E123')
    expect(row[:work_date]).to eq('2025-12-01')
    expect(row[:pay_code]).to eq('REG')
    # 1h07m rounds to 1.00 with 15-min rounding
    expect(row[:hours]).to eq(1.0)
  end

  it 'emits missing_employee_id errors and skips rows' do
    staff = create(:staff_member, business: business, adp_employee_id: nil)
    create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 10), end_time: Time.utc(2025, 12, 1, 11))

    rows, summary, report = described_class.new(business: business, config: config).build(
      range_start: Date.new(2025, 12, 1),
      range_end: Date.new(2025, 12, 1)
    )

    expect(rows).to be_empty
    expect(summary[:row_count]).to eq(0)
    expect(report[:errors].length).to eq(1)
    expect(report[:errors].first[:type]).to eq('missing_employee_id')
  end

  it 'rounds after aggregation (prevents undercounting)' do
    staff = create(:staff_member, business: business, adp_employee_id: 'E123', adp_pay_code: 'REG')
    create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 10, 0), end_time: Time.utc(2025, 12, 1, 10, 7))
    create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 11, 0), end_time: Time.utc(2025, 12, 1, 11, 7))

    rows, summary, report = described_class.new(business: business, config: config).build(
      range_start: Date.new(2025, 12, 1),
      range_end: Date.new(2025, 12, 1)
    )

    expect(report[:errors]).to be_empty
    expect(summary[:row_count]).to eq(1)
    expect(rows.first[:hours]).to eq(0.25)
  end
end
