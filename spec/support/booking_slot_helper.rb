# frozen_string_literal: true

module BookingSlotHelper
  # The public booking form offers radio buttons for open slots instead of
  # the old datetime_select dropdowns. The inputs are visually hidden.
  def choose_first_open_booking_slot
    expect(page).to have_css('input[name="booking[slot_choice]"]', visible: :all, wait: 10)
    first('input[name="booking[slot_choice]"]', visible: :all).click
  end
end

RSpec.configure do |config|
  config.include BookingSlotHelper, type: :system
end
