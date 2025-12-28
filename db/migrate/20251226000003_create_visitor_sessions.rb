# frozen_string_literal: true

class CreateVisitorSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :visitor_sessions do |t|
      t.references :business, null: false, foreign_key: true, index: true
      
      # Visitor identification
      t.string :visitor_fingerprint, null: false
      t.string :session_id, null: false, index: { unique: true }
      
      # Session timing
      t.datetime :session_start, null: false
      t.datetime :session_end
      t.integer :duration_seconds, default: 0 # Total session duration
      
      # Engagement metrics
      t.integer :page_view_count, default: 0
      t.integer :click_count, default: 0
      t.integer :pages_visited, default: 0
      t.boolean :is_bounce, default: false
      
      # Entry/exit info
      t.string :entry_page
      t.string :exit_page
      
      # Traffic source (first touch)
      t.string :first_referrer_url
      t.string :first_referrer_domain
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      
      # Device info
      t.string :device_type
      t.string :browser
      t.string :os
      t.string :country
      t.string :region
      t.string :city
      
      # Conversion tracking
      t.boolean :converted, default: false
      t.string :conversion_type # booking, purchase, estimate_request, contact
      t.decimal :conversion_value, precision: 10, scale: 2
      t.datetime :conversion_time
      
      # Return visitor tracking
      t.boolean :is_returning_visitor, default: false
      t.integer :previous_session_count, default: 0

      t.timestamps
    end

    # Performance indexes
    add_index :visitor_sessions, [:business_id, :created_at]
    add_index :visitor_sessions, [:visitor_fingerprint, :created_at]
    add_index :visitor_sessions, [:business_id, :session_start]
    add_index :visitor_sessions, [:business_id, :converted]
    add_index :visitor_sessions, :is_bounce
  end
end

