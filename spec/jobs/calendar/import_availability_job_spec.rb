# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Calendar::ImportAvailabilityJob, type: :job do
  let(:business) { create(:business) }
  let(:staff_member) { create(:staff_member, business: business) }

  before do
    allow(AvailabilityService).to receive(:clear_staff_availability_cache)
  end

  it 'clears staff cache and schedules next run' do
    described_class.perform_now(staff_member.id, Date.current, 1.day.from_now.to_date)

    expect(AvailabilityService).to have_received(:clear_staff_availability_cache).with(staff_member)
  end
end