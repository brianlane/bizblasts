namespace :tenant do
  desc "Create a new tenant with the given name"
  task :create, [:name] => :environment do |t, args|
    puts "Creating new tenant: #{args[:name]}"
    # Implementation would go here
  end

  desc "Delete a tenant with the given name"
  task :delete, [:name] => :environment do |t, args|
    puts "Deleting tenant: #{args[:name]}"
    # Implementation would go here
  end

  desc "List all tenants"
  task list: :environment do
    puts "Listing all tenants:"
    # Implementation would go here
  end
end
