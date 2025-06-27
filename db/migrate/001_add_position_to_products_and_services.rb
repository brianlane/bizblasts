class AddPositionToProductsAndServices < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :position, :integer, default: 0
    add_column :services, :position, :integer, default: 0
    
    # Add indexes for efficient ordering
    add_index :products, [:business_id, :position]
    add_index :services, [:business_id, :position]
    
    # Set initial positions for existing records
    reversible do |dir|
      dir.up do
        # Set positions for existing products, ordered by created_at
        Business.includes(:products).each do |business|
          business.products.order(:created_at).each_with_index do |product, index|
            product.update_column(:position, index)
          end
        end
        
        # Set positions for existing services, ordered by created_at
        Business.includes(:services).each do |business|
          business.services.order(:created_at).each_with_index do |service, index|
            service.update_column(:position, index)
          end
        end
      end
    end
  end
end 