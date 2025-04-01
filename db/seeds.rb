# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
puts "Creating default tenant..."
default_company = Company.find_or_create_by!(name: 'Default Company', subdomain: 'default')
puts "Default tenant created: #{default_company.name} (#{default_company.subdomain})"

# Create an admin user in the public schema
puts "Creating admin user..."
admin_user = User.find_or_initialize_by(email: 'admin@example.com')
if admin_user.new_record?
  admin_user.password = 'password123'
  admin_user.save!
  puts "Admin user created with email: #{admin_user.email} and password: password123"
else
  puts "Admin user already exists: #{admin_user.email}"
end

puts "Main database seeding completed!"