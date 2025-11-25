class CreateEstimates < ActiveRecord::Migration[8.0]
  def change
    create_table :estimates do |t|
      t.references :business, null: false, foreign_key: true
      t.references :tenant_customer, null: true, foreign_key: true
      t.datetime :proposed_start_time
      t.datetime :proposed_end_time
      t.string :token, null: false
      t.string :first_name
      t.string :last_name
      t.string :email
      t.string :phone
      t.string :address
      t.string :city
      t.string :state
      t.string :zip
      t.text :customer_notes
      t.text :internal_notes
      t.decimal :subtotal, precision: 10, scale: 2
      t.decimal :taxes, precision: 10, scale: 2
      t.decimal :required_deposit, precision: 10, scale: 2
      t.decimal :total, precision: 10, scale: 2
      t.integer :status, default: 0
      t.datetime :sent_at
      t.datetime :viewed_at
      t.datetime :approved_at
      t.datetime :declined_at
      t.datetime :deposit_paid_at
      t.references :booking, null: true, foreign_key: true

      t.timestamps
    end
  end
end
