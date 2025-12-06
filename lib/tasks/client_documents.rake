namespace :client_documents do
  desc 'Backfill client documents for existing estimates and rental bookings. Set BUSINESS_ID to limit scope.'
  task backfill: :environment do
    scope = if ENV['BUSINESS_ID'].present?
              Business.where(id: ENV['BUSINESS_ID'])
            else
              Business.all
            end

    totals = { estimates: 0, rentals: 0, errors: 0 }

    scope.find_each do |business|
      ActsAsTenant.with_tenant(business) do
        puts "Processing #{business.name} (##{business.id})"

        business.estimates.where.missing(:client_document).find_each do |estimate|
          begin
            estimate.ensure_client_document!
            totals[:estimates] += 1
          rescue => e
            totals[:errors] += 1
            warn "[client_documents.backfill] Estimate ##{estimate.id} failed: #{e.message}"
          end
        end

        business.rental_bookings.where.missing(:client_document).find_each do |booking|
          next unless booking.security_deposit_amount.to_f.positive?

          begin
            booking.ensure_client_document!
            totals[:rentals] += 1
          rescue => e
            totals[:errors] += 1
            warn "[client_documents.backfill] Rental Booking ##{booking.id} failed: #{e.message}"
          end
        end
      end
    end

    puts "Backfill complete – Estimates: #{totals[:estimates]}, Rentals: #{totals[:rentals]}, Errors: #{totals[:errors]}"
  end
end
