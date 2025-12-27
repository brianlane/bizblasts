# frozen_string_literal: true

class CreatePageViews < ActiveRecord::Migration[8.0]
  def change
    create_table :page_views do |t|
      t.references :business, null: false, foreign_key: true, index: true
      t.references :page, null: true, foreign_key: true
      
      # Visitor identification (anonymous)
      t.string :visitor_fingerprint, null: false
      t.string :session_id, null: false
      
      # Page information
      t.string :page_path, null: false
      t.string :page_type # home, services, products, booking, contact, custom
      t.string :page_title
      
      # Traffic source
      t.string :referrer_url
      t.string :referrer_domain
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.string :utm_term
      t.string :utm_content
      
      # Device/browser info
      t.string :device_type # mobile, tablet, desktop
      t.string :browser
      t.string :browser_version
      t.string :os
      t.string :os_version
      t.string :screen_resolution
      
      # Geo (approximate, from IP)
      t.string :country
      t.string :region
      t.string :city
      
      # Engagement metrics
      t.integer :time_on_page # seconds, updated on next page view or exit
      t.integer :scroll_depth # percentage 0-100
      t.boolean :is_entry_page, default: false
      t.boolean :is_exit_page, default: false
      t.boolean :is_bounce, default: false

      t.timestamps
    end

    # Performance indexes
    add_index :page_views, [:business_id, :created_at]
    add_index :page_views, [:visitor_fingerprint, :created_at]
    add_index :page_views, [:session_id, :created_at]
    add_index :page_views, [:business_id, :page_path]
    add_index :page_views, :referrer_domain
    add_index :page_views, :device_type
  end
end

