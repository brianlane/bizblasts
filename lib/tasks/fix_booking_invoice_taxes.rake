namespace :invoices do
  desc "Fix existing booking-based invoices to include tax rates and recalculate totals"
  task fix_booking_taxes: :environment do
    puts "Starting to fix booking-based invoices without tax rates..."
    
    # Find all booking-based invoices without tax rates
    invoices_to_fix = Invoice.joins(:booking).where(tax_rate_id: nil)
    
    puts "Found #{invoices_to_fix.count} booking-based invoices without tax rates"
    
    fixed_count = 0
    error_count = 0
    
    invoices_to_fix.find_each do |invoice|
      begin
        # Get the business's default tax rate
        default_tax_rate = invoice.business.default_tax_rate
        
        if default_tax_rate
          # Store original amounts for comparison
          original_tax = invoice.tax_amount
          original_total = invoice.total_amount
          
          # Assign tax rate and recalculate
          invoice.update!(tax_rate: default_tax_rate)
          
          puts "Fixed Invoice #{invoice.invoice_number}:"
          puts "  Tax: $#{original_tax} → $#{invoice.tax_amount}"
          puts "  Total: $#{original_total} → $#{invoice.total_amount}"
          puts ""
          
          fixed_count += 1
        else
          puts "Warning: Business #{invoice.business.name} has no default tax rate"
        end
      rescue => e
        puts "Error fixing Invoice #{invoice.invoice_number}: #{e.message}"
        error_count += 1
      end
    end
    
    puts "Completed!"
    puts "Fixed: #{fixed_count} invoices"
    puts "Errors: #{error_count} invoices"
  end
end 