FactoryBot.define do
  factory :notification_template do
    business
    event_type { "booking_confirmed" }
    channel { "email" }
    subject { "Booking Confirmation" }
    body { "Your booking has been confirmed." }
  end
end 