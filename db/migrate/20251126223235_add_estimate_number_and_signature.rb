class AddEstimateNumberAndSignature < ActiveRecord::Migration[8.0]
  def change
    add_column :estimates, :estimate_number, :string
    add_index :estimates, [:business_id, :estimate_number], unique: true

    # Signature fields
    add_column :estimates, :signature_data, :text # Base64 encoded signature image
    add_column :estimates, :signature_name, :string
    add_column :estimates, :signed_at, :datetime

    # PDF generation tracking
    add_column :estimates, :pdf_generated_at, :datetime
  end
end
