namespace :booking_stats do
  desc "Generate booking statistics report for all tenants"
  task generate: :environment do
    puts "Generating booking statistics report"
    # Implementation would go here
  end

  desc "Generate booking statistics report for a specific tenant"
  task :generate_for_tenant, [:tenant_name] => :environment do |t, args|
    puts "Generating booking statistics report for tenant: #{args[:tenant_name]}"
    # Implementation would go here
  end
end
