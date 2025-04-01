class CreateBookingSystem < ActiveRecord::Migration[8.0]
  def change
    create_table :services do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.decimal :price, precision: 10, scale: 2
      t.integer :duration_minutes
      t.boolean :active, default: true
      t.jsonb :settings, default: {}
      t.text :notes

      t.timestamps
    end

    create_table :service_providers do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.boolean :active, default: true
      t.jsonb :availability, default: {}
      t.jsonb :settings, default: {}
      t.text :notes

      t.timestamps
    end

    create_table :appointments do |t|
      t.references :company, null: false, foreign_key: true
      t.references :service, null: false, foreign_key: true
      t.references :service_provider, null: false, foreign_key: true
      t.string :client_name, null: false
      t.string :client_email
      t.string :client_phone
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.string :status, default: 'scheduled'
      t.decimal :price, precision: 10, scale: 2
      t.text :notes
      t.jsonb :metadata, default: {}
      t.string :stripe_payment_intent_id
      t.string :stripe_customer_id
      t.boolean :paid, default: false
      t.datetime :cancelled_at
      t.text :cancellation_reason

      t.timestamps
    end

    create_table :business_hours do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :day_of_week, null: false
      t.time :open_time
      t.time :close_time
      t.boolean :is_closed, default: false
      t.text :notes

      t.timestamps
    end

    add_index :services, %i[company_id name], unique: true
    add_index :services, :active
    add_index :service_providers, %i[company_id name], unique: true
    add_index :service_providers, :active
    add_index :appointments, %i[company_id start_time]
    add_index :appointments, :status
    add_index :appointments, :paid
    add_index :business_hours, %i[company_id day_of_week], unique: true
  end
end
