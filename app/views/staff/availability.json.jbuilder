json.staff_member do
  json.id @staff_member.id
  json.name @staff_member.name
end

json.calendar_data @calendar_data

json.date @date
json.start_date @start_date
json.end_date @end_date

json.services @services do |service|
  json.id service.id
  json.name service.name
  json.price service.price
  json.duration service.duration
end 