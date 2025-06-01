namespace :data_integrity do
  desc "Check for line items with missing product variants"
  task :check_orphaned_line_items => :environment do
    puts "Checking for line items with missing product variants..."
    
    # Find line items with product_variant_id that don't have actual product variants
    orphaned_line_items = LineItem.includes(:product_variant)
                                  .where.not(product_variant_id: nil)
                                  .where(product_variants: { id: nil })
    
    if orphaned_line_items.any?
      puts "Found #{orphaned_line_items.count} orphaned line items:"
      orphaned_line_items.find_each do |item|
        puts "  LineItem ID: #{item.id}, Product Variant ID: #{item.product_variant_id}, Lineable: #{item.lineable_type} ##{item.lineable_id}"
      end
      
      puts "\nTo fix these, you can either:"
      puts "1. Run the cleanup task: rake data_integrity:cleanup_orphaned_line_items"
      puts "2. Manually investigate and fix the data inconsistencies"
    else
      puts "No orphaned line items found. Data integrity looks good!"
    end
  end
  
  desc "Clean up orphaned line items (sets product_variant_id to nil)"
  task :cleanup_orphaned_line_items => :environment do
    puts "Cleaning up orphaned line items..."
    
    orphaned_line_items = LineItem.includes(:product_variant)
                                  .where.not(product_variant_id: nil)
                                  .where(product_variants: { id: nil })
    
    count = orphaned_line_items.count
    if count > 0
      puts "Found #{count} orphaned line items. Setting product_variant_id to nil..."
      
      orphaned_line_items.update_all(product_variant_id: nil)
      
      puts "Cleanup complete. #{count} line items updated."
      puts "Note: These line items will now show as 'Product no longer available' in the UI."
    else
      puts "No orphaned line items found to clean up."
    end
  end
end 