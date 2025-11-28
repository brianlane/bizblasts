class AddPendingPaymentStatusToEstimates < ActiveRecord::Migration[8.0]
  def change
    # Note: pending_payment status (value 6) will be added to the enum in the model
    # No migration needed for enum values, just update the model

    # Add payment tracking fields
    add_column :estimates, :payment_intent_id, :string
    add_column :estimates, :checkout_session_id, :string
    add_index :estimates, :payment_intent_id
    add_index :estimates, :checkout_session_id
  end
end
