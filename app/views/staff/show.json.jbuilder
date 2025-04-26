json.staff_member do
  json.id @staff_member.id
  json.name @staff_member.name
  json.email @staff_member.email
  json.phone @staff_member.phone
  json.position @staff_member.position
  json.bio @staff_member.bio
  json.active @staff_member.active
  json.photo_url @staff_member.photo_url
  
  json.services @staff_member.services do |service|
    json.id service.id
    json.name service.name
    json.price service.price
    json.duration service.duration
  end
end 