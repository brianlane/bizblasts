# frozen_string_literal: true

class CreateClickEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :click_events do |t|
      t.references :business, null: false, foreign_key: true, index: true
      
      # Visitor identification
      t.string :visitor_fingerprint, null: false
      t.string :session_id, null: false
      
      # Element information
      t.string :element_type, null: false # button, link, cta, form_submit
      t.string :element_identifier # CSS selector, data attribute, or ID
      t.string :element_text, limit: 255 # Truncated text content
      t.string :element_class
      t.string :element_href
      
      # Context
      t.string :page_path, null: false
      t.string :page_title
      
      # Target (what was clicked)
      t.string :category # booking, product, service, contact, navigation, social, estimate
      t.string :action # view, add_to_cart, book, submit, call, email
      t.string :label # Additional context (e.g., product name)
      
      # Polymorphic target reference
      t.string :target_type # Service, Product, StaffMember, etc.
      t.bigint :target_id
      
      # Conversion tracking
      t.decimal :conversion_value, precision: 10, scale: 2 # Potential revenue value
      t.boolean :is_conversion, default: false
      t.string :conversion_type # booking_started, booking_completed, purchase, estimate_request
      
      # Position data
      t.integer :click_x
      t.integer :click_y
      t.integer :viewport_width
      t.integer :viewport_height

      t.timestamps
    end

    # Performance indexes
    add_index :click_events, [:business_id, :created_at]
    add_index :click_events, [:visitor_fingerprint, :created_at]
    add_index :click_events, [:session_id, :created_at]
    add_index :click_events, [:business_id, :category]
    add_index :click_events, [:target_type, :target_id]
    add_index :click_events, :is_conversion
  end
end

