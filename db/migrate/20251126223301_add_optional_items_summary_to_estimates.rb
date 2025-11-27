class AddOptionalItemsSummaryToEstimates < ActiveRecord::Migration[8.0]
  def change
    # Track optional items separately for clear display
    add_column :estimates, :optional_items_subtotal, :decimal, precision: 10, scale: 2, default: 0
    add_column :estimates, :optional_items_taxes, :decimal, precision: 10, scale: 2, default: 0
    add_column :estimates, :has_optional_items, :boolean, default: false, null: false

    add_index :estimates, :has_optional_items
    add_index :estimates, :status
  end
end
