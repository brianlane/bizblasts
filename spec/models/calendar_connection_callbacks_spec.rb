# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalendarConnection, type: :model do
  describe 'callbacks' do
    let(:business) { create(:business) }
    let(:staff_member) { create(:staff_member, business: business) }

    it 'clears availability cache on create and destroy' do
      expect_any_instance_of(CalendarConnection).to receive(:clear_staff_availability_cache).once.and_call_original

      connection = create(:calendar_connection, :google, staff_member: staff_member, business: business)
      connection.destroy
    end

    it 'clears cache on mark_synced!' do
      expect_any_instance_of(CalendarConnection).to receive(:clear_staff_availability_cache).at_least(:once).and_call_original
      connection = create(:calendar_connection, :google, staff_member: staff_member, business: business)

      connection.mark_synced!
    end
  end
end