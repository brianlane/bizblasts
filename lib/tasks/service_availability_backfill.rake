namespace :service do
  desc 'Backfill services with default availability and enforce flag'
  task backfill_availability: :environment do
    Service.find_each do |service|
      service.update_columns(availability: {}, enforce_service_availability: true)
    end
    puts 'Backfilled availability and enforce flags for all services'
  end
end 