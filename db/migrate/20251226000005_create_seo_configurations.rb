# frozen_string_literal: true

class CreateSeoConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :seo_configurations do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }
      
      # Meta tag templates
      t.string :meta_title_template # "{{business_name}} | {{page_title}} in {{city}}"
      t.text :meta_description_template
      t.text :keywords, array: true, default: []
      
      # Social media
      t.string :og_title_template
      t.text :og_description_template
      t.string :twitter_handle
      
      # Google verification
      t.string :google_site_verification
      t.string :google_analytics_id
      t.string :google_tag_manager_id
      
      # Local SEO
      t.jsonb :local_business_schema, default: {}
      # Pre-computed LocalBusiness structured data
      
      # Target keywords for ranking tracking
      t.text :target_keywords, array: true, default: []
      t.text :competitor_domains, array: true, default: []
      
      # SEO score tracking
      t.integer :seo_score, default: 0 # 0-100
      t.jsonb :seo_score_breakdown, default: {}
      # { title_score: 80, description_score: 75, content_score: 60, ... }
      
      t.jsonb :seo_suggestions, default: []
      # [{ priority: 'high', category: 'title', suggestion: '...', impact: 15 }, ...]
      
      # Keyword ranking estimates
      t.jsonb :keyword_rankings, default: {}
      # { "hair salon portland": { position: 15, trend: "improving", last_checked: "..." }, ... }
      
      # Auto-generated keywords based on business details
      t.jsonb :auto_keywords, default: []
      # Generated from business name, services, location, industry
      
      # Sitemap configuration
      t.boolean :sitemap_enabled, default: true
      t.string :sitemap_priority, default: '0.8'
      t.string :sitemap_changefreq, default: 'weekly'
      
      # Robots configuration
      t.boolean :allow_indexing, default: true
      t.text :robots_txt_additions
      
      t.datetime :last_analysis_at
      t.datetime :last_keyword_check_at

      t.timestamps
    end
  end
end

