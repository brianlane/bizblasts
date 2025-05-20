class AddServiceAndStaffToLineItems < ActiveRecord::Migration[8.0]
  def change
    # Add service reference for service line items
    add_reference :line_items, :service, foreign_key: true, type: :bigint
    # Add staff member reference for tracking service assignment
    add_reference :line_items, :staff_member, foreign_key: true, type: :bigint
  end
end 