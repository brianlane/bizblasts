FactoryBot.define do
  factory :location do
    business
    name { "Downtown Office" }
    address { "123 Main St" }
    city { "San Francisco" }
    state { "CA" }
    zip { "94105" }
    hours { { mon: { open: "09:00", close: "17:00" }, tue: { open: "09:00", close: "17:00" }, wed: { open: "09:00", close: "17:00" }, thu: { open: "09:00", close: "17:00" }, fri: { open: "09:00", close: "17:00" } } }
  end
end 