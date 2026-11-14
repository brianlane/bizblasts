# frozen_string_literal: true

module BookingSlotHelper
  # The public booking form offers radio buttons for open slots instead of
  # the old datetime_select dropdowns. The inputs are visually hidden.
  def choose_first_open_booking_slot
    expect(page).to have_css('[role="radiogroup"] label', text: 'Select this time', wait: 10)
    first('[role="radiogroup"] label', text: 'Select this time').click
  end
end

RSpec.configure do |config|
  config.include BookingSlotHelper, type: :system
end
