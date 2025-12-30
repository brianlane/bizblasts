# frozen_string_literal: true

class AddHeatmapIndexToClickEvents < ActiveRecord::Migration[8.0]
  def change
    # Index for heatmap and element popularity queries
    # Speeds up queries that filter by business, element type, and page path
    add_index :click_events, [:business_id, :element_type, :page_path, :created_at],
              name: "index_click_events_heatmap"
  end
end
