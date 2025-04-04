namespace :setup do
  desc "Create an admin user for ActiveAdmin access"
  task create_admin: :environment do
    email = ENV['ADMIN_EMAIL'] || 'admin@example.com'
    password = ENV['ADMIN_PASSWORD'] || 'password123'
    
    unless AdminUser.exists?(email: email)
      admin = AdminUser.create!(
        email: email,
        password: password,
        password_confirmation: password
      )
      puts "Created AdminUser: #{admin.email} with password: #{password}"
    else
      puts "AdminUser with email #{email} already exists"
    end
  end
  
  desc "Set up all required data for tests"
  task test_setup: [:create_admin] do
    puts "Test setup completed!"
  end
end 